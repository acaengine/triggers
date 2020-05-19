require "./helper"

module PlaceOS::Model
  describe Trigger do
    redis = PlaceOS::Driver::Storage.redis_pool

    Spec.after_suite {
      store = PlaceOS::Driver::Storage.new("mod-1234")
      store.clear
    }

    it "validates comparison condition" do
      trigger = Generator.trigger
      valid = Trigger::Conditions::Comparison.new(
        left: true,
        operator: "and",
        right: {
          mod:    "Test_1",
          status: "state",
          keys:   ["on"],
        }
      )
      trigger.conditions.try &.comparisons = [valid]
      trigger.valid?.should be_true
      trigger.save!

      inst = Generator.trigger_instance(trigger).save!

      # allow time for the database to propagate the config
      sleep 0.1

      # create the status lookup structure
      sys_id = inst.control_system_id.not_nil!
      storage = PlaceOS::Driver::Storage.new(sys_id, "system")
      storage["Test/1"] = "mod-1234"

      # signal a change in lookup state
      redis.publish "lookup-change", sys_id

      sleep 0.1

      # Ensure the trigger hasn't fired
      state = ::LOADER.instances[inst.id]
      state.triggered.should be_false

      store = PlaceOS::Driver::Storage.new("mod-1234")
      store[:state] = {on: true}.to_json

      sleep 0.1

      # ensure the trigger has fired
      state.triggered.should be_true
    end
  end
end
