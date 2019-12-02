require "engine-models"
require "rethinkdb-orm"

require "./state"

module ACAEngine::Triggers
  class Loader
    @trigger_cache = {} of String => Model::Trigger
    @trigger_map = {} of String => Array(State)
    @instances = {} of String => State

    def load!
      spawn(same_thread: true) { watch_triggers! }
      spawn(same_thread: true) { watch_instances! }

      Fiber.yield

      Model::TriggerInstance.all.each &->new_instance(Model::TriggerInstance)
    end

    private def watch_triggers!
      Model::Trigger.changes.each do |change|
        trigger = change[:value]

        case change[:event]
        when RethinkORM::Changefeed::Event::Deleted
          @trigger_cache.delete trigger.id
          triggers = @trigger_map.delete(trigger.id)
          triggers.try &.each do |state|
            @instances.delete state.instance_id
            state.terminate!
          end
        when RethinkORM::Changefeed::Event::Created
          @trigger_cache[trigger.id] = trigger
        when RethinkORM::Changefeed::Event::Updated
          @trigger_cache[trigger.id] = trigger
          states = @trigger_map.delete(trigger.id)
          states.each do |state|
            instance = state.instance
            @instances.delete(instance.id)
            state.terminate!

            new_instance(trigger, instance)
          end
        end
      end
    end

    private def watch_instances!
      Model::TriggerInstance.changes.each do |change|
        instance = change[:value]

        case change[:event]
        when RethinkORM::Changefeed::Event::Deleted
          remove_instance(instance)
        when RethinkORM::Changefeed::Event::Created
          new_instance(instance)
        when RethinkORM::Changefeed::Event::Updated
          remove_instance(instance)
          new_instance(instance)
        end
      end
    end

    def new_instance(instance)
      trigger_id = instance.trigger_id
      trig = @trigger_cache[trigger_id]?
      trigger = if trig
                  trig
                else
                  @trigger_cache[trigger_id] = instance.trigger.not_nil!
                end

      new_instance(trigger, instance)
    end

    def new_instance(trigger, instance)
      state = State.new trigger, instance
      @instances[instance.id] = state
      states = @trigger_map[trigger_id]?
      if states
        states << state
      else
        @trigger_map[trigger_id] = [state]
      end

      state
    end

    def remove_instance(instance)
      state = @instances[instance.id]?
      if state
        instances = @trigger_map[instance.trigger_id]?
        instances.try &.delete(state)
        state.terminate!
      end

      nil
    end
  end
end
