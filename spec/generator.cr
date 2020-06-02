require "random"
require "placeos-models"

RANDOM = Random.new

module PlaceOS::Model
  # Defines generators for models
  module Generator
    def self.trigger(system : ControlSystem? = nil)
      trigger = Trigger.new(
        name: RANDOM.base64(10),
      )
      trigger.control_system = system if system
      trigger
    end

    def self.trigger_instance(trigger = nil, zone = nil, control_system = nil)
      trigger = self.trigger.save! unless trigger
      instance = TriggerInstance.new(important: false)
      instance.trigger = trigger

      instance.zone = zone if zone

      instance.control_system = control_system ? control_system : self.control_system.save!

      instance
    end

    def self.control_system
      ControlSystem.new(
        name: RANDOM.base64(10),
      )
    end
  end
end
