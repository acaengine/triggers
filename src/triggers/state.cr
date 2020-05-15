require "models"
require "hound-dog"
require "tasker"

require "json"
require "redis"
require "driver/storage"
require "driver/subscriptions"
require "driver/proxy/subscriptions"
require "driver/proxy/remote_driver"

# NOTE:: webhooks should allow drivers to process and provide responses
# JohnsonControls => posts xml, expects a 200 response (no security)
# Meraki
# => get route, return secret
# => post json, return 200
# CogniPoint => post json, return 200 (header token)

module PlaceOS::Triggers
  class State
    @@subscriber = PlaceOS::Driver::Subscriptions.new

    def initialize(@trigger : Model::Trigger, @instance : Model::TriggerInstance)
      @terminated = false
      @trigger_id = @trigger.id.not_nil!
      @instance_id = @instance.id.not_nil!
      @subscriptions = PlaceOS::Driver::Proxy::Subscriptions.new(@@subscriber)

      @conditions_met = {} of String => Bool
      @condition_timers = [] of Tasker::Task
      @debounce_timers = {} of String => Tasker::Task
      @comparisons = [] of Comparison

      @schedule = Tasker.instance

      @triggered = false
      @storage = PlaceOS::Driver::Storage.new(@instance_id)
      @storage.clear
      @storage["state"] = %({"triggered":false})
      @conditions_met["triggered"] = false
      @conditions_met["webhook"] = false if @trigger.enable_webhook

      # New thread!
      spawn { monitor! }
    end

    getter trigger_id : String
    getter instance_id : String
    getter trigger : Model::Trigger
    getter instance : Model::TriggerInstance

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
        @comparisons << Comparison.new(
          self,
          "comparison_#{index}",
          system_id,
          comparison.left.not_nil!,
          comparison.operator.not_nil!,
          comparison.right.not_nil!
        )
      end
    end

    def set_condition(key : String, state : Bool)
      @conditions_met[key] = state
      check_trigger!
    end

    def check_trigger!
      update_state !@conditions_met.values.includes?(false)
    end

    def update_state(triggered : Bool)
      # Check if there was change
      return if triggered == @triggered
      @triggered = triggered
      @conditions_met["triggered"] = triggered
      @storage["state"] = @conditions_met.to_json

      # Check if we should run the actions
      return unless triggered

      # perform actions
      system_id = @instance.control_system_id.not_nil!
      actions = @trigger.actions.not_nil!

      actions.functions.not_nil!.each_with_index do |action, function_index|
        modname, index = PlaceOS::Driver::Proxy::RemoteDriver.get_parts(action.mod.not_nil!)
        method = action.method.not_nil!
        args = action.args.not_nil!

        # TODO:: we should use the same caching system that is used by the websocket API
        begin
          # NOTE:: do we want to process the response here?
          PlaceOS::Driver::Proxy::RemoteDriver.new(
            system_id,
            modname,
            index
          ).exec(
            PlaceOS::Driver::Proxy::RemoteDriver::Clearance::Admin,
            method,
            named_args: args,
            request_id: "action_#{function_index}_#{Time.utc.to_unix_ms}"
          )
        rescue error
          # TODO:: log the errors
        end
      end

      mailers = actions.mailers.not_nil!
      if !mailers.empty?
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
        rescue e
          # TODO:: log the error
          # Potentially this should be done in sidekiq or similar?
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
