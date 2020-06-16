require "hound-dog"
require "placeos-models"
require "tasker"

require "json"
require "placeos-driver/storage"
require "placeos-driver/subscriptions"
require "placeos-driver/proxy/subscriptions"
require "placeos-driver/proxy/remote_driver"

# NOTE:: webhooks should allow drivers to process and provide responses
# JohnsonControls => posts xml, expects a 200 response (no security)
# Meraki
# => get route, return secret
# => post json, return 200
# CogniPoint => post json, return 200 (header token)

module PlaceOS::Triggers
  class State
    Log = ::App::Log.for("state")

    @@subscriber = PlaceOS::Driver::Subscriptions.new

    def initialize(@trigger : Model::Trigger, @instance : Model::TriggerInstance)
      @terminated = false
      @trigger_id = @trigger.id.not_nil!
      @instance_id = @instance.id.not_nil!
      @subscriptions = PlaceOS::Driver::Proxy::Subscriptions.new(@@subscriber)

      @conditions_met = {} of String => Bool
      @conditions_met["webhook"] = false if @trigger.enable_webhook

      @condition_timers = [] of Tasker::Task
      @debounce_timers = {} of String => Tasker::Task
      @comparisons = [] of Comparison

      @schedule = Tasker.instance

      @triggered = false
      @count = 0_i64
      @comparison_errors = 0_i64
      @action_errors = 0_i64
      @storage = PlaceOS::Driver::Storage.new(@instance_id)
      @storage.clear
      publish_state

      # New thread!
      spawn { monitor! }
    end

    getter trigger_id : String
    getter instance_id : String
    getter trigger : Model::Trigger
    getter instance : Model::TriggerInstance
    getter triggered : Bool
    getter count : Int64

    def terminate!
      @terminated = true

      # cancel timers
      @condition_timers.each(&.cancel)
      @debounce_timers.each_value(&.cancel)
      @condition_timers.clear
      @debounce_timers.clear

      # cancel subscriptions
      @subscriptions.terminate
    end

    def monitor!
      return if @terminated

      conditions = @trigger.conditions.not_nil!

      # Build the time triggers
      times = conditions.time_dependents.not_nil!
      times.each_with_index do |time, index|
        condition_key = "time_#{index}"
        @conditions_met[condition_key] = false

        case time.type
        when PlaceOS::Model::Trigger::Conditions::TimeDependent::Type::At
          time_at(condition_key, time.time.not_nil!)
        when PlaceOS::Model::Trigger::Conditions::TimeDependent::Type::Cron
          time_cron(condition_key, time.cron.not_nil!)
        else
          raise "invalid type: #{time.type.inspect}"
        end
      end

      # monitor status values to track conditions
      system_id = @instance.control_system_id.not_nil!
      comparisons = conditions.comparisons.not_nil!
      comparisons.each_with_index do |comparison, index|
        condition_key = "comparison_#{index}"
        @conditions_met[condition_key] = false

        @comparisons << Comparison.new(
          self,
          condition_key,
          system_id,
          comparison.left.not_nil!,
          comparison.operator.not_nil!,
          comparison.right.not_nil!
        )
      end

      @comparisons.each(&.bind!(@subscriptions))
    rescue error
      Log.error(exception: error) { {
        system_id: @instance.control_system_id,
        trigger:   @instance.trigger_id,
        instance:  @instance.id,
        message:   "failed to initialize trigger instance '#{@trigger.name}'",
      } }
    end

    def set_condition(key : String, state : Bool)
      @conditions_met[key] = state
      check_trigger!
    end

    def check_trigger!
      update_state !@conditions_met.values.includes?(false)
    end

    def increment_action_error
      begin
        @action_errors += 1
      rescue OverflowError
        @action_errors = 1
      end
      publish_state
    end

    def increment_comparison_error
      begin
        @comparison_errors += 1
      rescue OverflowError
        @comparison_errors = 1
      end
      publish_state
    end

    def publish_state
      @storage["state"] = {
        triggered:         @triggered,
        trigger_count:     @count,
        action_errors:     @action_errors,
        comparison_errors: @comparison_errors,
        conditions:        @conditions_met,
      }.to_json
    end

    def update_state(triggered : Bool)
      # Check if there was change
      return if triggered == @triggered
      if triggered
        begin
          @count += 1
        rescue OverflowError
          @count = 0_i64
        end
      end

      @triggered = triggered
      publish_state

      Log.info { {
        system_id: @instance.control_system_id,
        trigger:   @instance.trigger_id,
        instance:  @instance.id,
        message:   "state changed to #{triggered}",
      } }

      # Check if we should run the actions
      return unless triggered

      # perform actions
      system_id = @instance.control_system_id.not_nil!
      actions = @trigger.actions.not_nil!

      actions.functions.not_nil!.each_with_index do |action, function_index|
        modname, index = PlaceOS::Driver::Proxy::RemoteDriver.get_parts(action.mod.not_nil!)
        method = action.method.not_nil!
        args = action.args.not_nil!
        request_id = "action_#{function_index}_#{Time.utc.to_unix_ms}"

        Log.debug { {
          system_id:  system_id,
          module:     modname,
          index:      index,
          method:     method,
          request_id: request_id,
          trigger:    @instance.trigger_id,
          instance:   @instance.id,
          message:    "performing exec for trigger '#{@trigger.name}'",
        } }

        begin
          PlaceOS::Driver::Proxy::RemoteDriver.new(
            system_id,
            modname,
            index,
            App.discovery
          ).exec(
            PlaceOS::Driver::Proxy::RemoteDriver::Clearance::Admin,
            method,
            named_args: args,
            request_id: request_id
          )
        rescue error
          Log.error(exception: error) { {
            system_id:  system_id,
            module:     modname,
            index:      index,
            method:     method,
            request_id: request_id,
            trigger:    @instance.trigger_id,
            instance:   @instance.id,
            message:    "exec failed for trigger '#{@trigger.name}'",
          } }
          increment_action_error
        end
      end

      mailers = actions.mailers.not_nil!
      if !mailers.empty?
        Log.debug { {
          system_id: @instance.control_system_id,
          trigger:   @instance.trigger_id,
          instance:  @instance.id,
          message:   "sending email for trigger '#{@trigger.name}'",
        } }

        begin
          # Create SMTP client object
          client = EMail::Client.new(::SMTP_CONFIG)
          client.start do
            mailers.each do |mail|
              content = mail.content.not_nil!
              mail.emails.not_nil!.each do |address|
                # TODO:: Complete subject and from addresses
                email = EMail::Message.new
                email.from "triggers@example.com"
                email.to address
                email.subject "triggered"
                email.message content

                send(email)
              end
            end
          end
        rescue error
          Log.error(exception: error) { {
            system_id: @instance.control_system_id,
            trigger:   @instance.trigger_id,
            instance:  @instance.id,
            message:   "email send failed for trigger '#{@trigger.name}'",
          } }
          increment_action_error
        end
      end
    end

    def time_at(key, time)
      @condition_timers << @schedule.at(time) { temporary_condition_met(key) }
    end

    def time_cron(key, cron)
      @condition_timers << @schedule.cron(cron) { temporary_condition_met(key) }
    end

    def temporary_condition_met(key : String)
      if timer = @debounce_timers[key]?
        timer.cancel
      end

      # Revert the status of this condition
      @debounce_timers[key] = @schedule.in(59.seconds) do
        @debounce_timers.delete key
        @conditions_met[key] = false
        update_state(false)
      end

      # Update status of this condition
      @conditions_met[key] = true
      check_trigger!
    end
  end
end
