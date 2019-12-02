require "engine-models"

module ACAEngine::Triggers
  class State
    def initialize(@trigger : Model::Trigger, @instance : Model::TriggerInstance)
      @terminated = false
      @trigger_id = @trigger.id.not_nil!
      @instance_id = @instance.id.not_nil!

      spawn(same_thread: true) { monitor! }
    end

    getter trigger_id : String
    getter instance_id : String
    getter trigger : Model::Trigger
    getter instance : Model::TriggerInstance

    def terminate!
      @terminated = true
    end

    def monitor!
      return if @terminated

      # conditions = trigger.conditions
      # TODO:: monitor status values to track conditions
      # conditions.comparisons.each do ||
    end
  end
end
