class State
  def initialize(@trigger : Engine::Model::Trigger, @instance : Engine::Model::TriggerInstance)
    @terminated = false
    @trigger_id = @trigger.id.not_nil!
    @instance_id = @instance.id.not_nil!



    spawn { monitor! }
  end

  getter trigger_id : String
  getter instance_id : String
  getter trigger : Engine::Model::Trigger
  getter instance : Engine::Model::TriggerInstance

  def terminate!
    @terminated = true
  end

  def monitor!
    return if @terminated

    conditions = trigger.conditions
    # TODO:: monitor status values to track conditions
    # conditions.comparisons.each do ||
  end
end
