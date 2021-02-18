require "placeos-models"
require "rethinkdb-orm"

require "./state"

module PlaceOS::Triggers
  class Loader
    Log = ::App::Log.for("loader")

    @trigger_cache = {} of String => Model::Trigger
    @trigger_map = {} of String => Array(State)

    getter instances = {} of String => State

    def load!
      # This ensures the change feeds are live before we load the trigger instances
      spawn(same_thread: true) { watch_triggers! }
      spawn(same_thread: true) { watch_instances! }
      spawn(same_thread: true) do
        begin
          Model::TriggerInstance.all.each &->new_instance(Model::TriggerInstance)
        rescue error
          Log.fatal(exception: error) { "failed to load trigger instances" }
          sleep 0.2
          exit 3
        end
      end
      Fiber.yield
    end

    private def watch_triggers!
      Model::Trigger.changes.each do |change|
        begin
          trigger = change[:value]

          Log.debug { {trigger: trigger.id, message: "trigger '#{trigger.name}' #{change[:event]}"} }

          case change[:event]
          in .deleted?
            @trigger_cache.delete trigger.id
            triggers = @trigger_map.delete(trigger.id)
            triggers.try &.each do |state|
              @instances.delete state.instance_id
              state.terminate!
            end
          in .created?
            @trigger_cache[trigger.id.not_nil!] = trigger
          in .updated?
            @trigger_cache[trigger.id.not_nil!] = trigger
            states = @trigger_map.delete(trigger.id)
            if states
              states.each do |state|
                instance = state.instance
                @instances.delete(instance.id)
                state.terminate!

                new_instance(trigger, instance)
              end
            end
          end
        rescue error
          Log.error(exception: error) { "trigger change failed" }
        end
      end
    rescue error
      Log.fatal(exception: error) { "trigger change feed failed" }
      sleep 0.2
      exit 1
    end

    private def watch_instances!
      Model::TriggerInstance.changes.each do |change|
        begin
          instance = change[:value]

          Log.debug { {trigger: instance.trigger_id, instance: instance.id, system_id: instance.control_system_id, message: "trigger instance #{change[:event]}"} }

          case change[:event]
          in .deleted?
            remove_instance(instance)
          in .created?
            new_instance(instance)
          in .updated?
            remove_instance(instance)
            new_instance(instance)
          end
        rescue error
          Log.error(exception: error) { "instance change failed" }
        end
      end
    rescue error
      Log.fatal(exception: error) { "trigger instance change feed failed" }
      sleep 0.2
      exit 2
    end

    def new_instance(instance)
      trigger_id = instance.trigger_id.not_nil!
      trig = @trigger_cache[trigger_id]?
      trigger = if trig
                  trig
                else
                  @trigger_cache[trigger_id] = instance.trigger.not_nil!
                end

      new_instance(trigger, instance)
    end

    def new_instance(trigger, instance)
      trigger_id = trigger.id.not_nil!
      state = State.new trigger, instance
      @instances[instance.id.not_nil!] = state
      if states = @trigger_map[trigger_id]?
        states << state
      else
        @trigger_map[trigger_id] = [state]
      end

      state
    end

    def remove_instance(instance)
      if state = @instances[instance.id]?
        @trigger_map[instance.trigger_id]?.try &.delete(state)
        state.terminate!
      end

      nil
    end
  end
end
