require "./helper"

module PlaceOS::Model
  describe Trigger do
    Spec.after_suite {
      store = PlaceOS::Driver::Storage.new("mod-1234")
      store.clear
    }

    it "creates a trigger, updates it and checks that exec works" do
      trigger = Generator.trigger
      compare = Trigger::Conditions::Comparison.new(
        left: true,
        operator: "and",
        right: {
          mod:    "Test_1",
          status: "state",
          keys:   ["on"],
        }
      )
      trigger.conditions.try &.comparisons = [compare]
      trigger.valid?.should be_true
      trigger.save!

      inst = Generator.trigger_instance(trigger).save!

      # allow time for the database to propagate the config
      sleep 0.1

      # create the status lookup structure
      sys_id = inst.control_system_id.not_nil!
      storage = PlaceOS::Driver::Storage.new(sys_id, "system")
      storage["Test/1"] = "mod-1234"

      PlaceOS::Driver::Subscriptions.new_redis.publish "lookup-change", sys_id

      sleep 0.1

      # signal a change in lookup state
      PlaceOS::Driver::Storage.with_redis do |redis|
        # Ensure the trigger hasn't fired
        state = ::LOADER.instances[inst.id]
        state.triggered.should be_false

        store = PlaceOS::Driver::Storage.new("mod-1234")
        store[:state] = {on: true}.to_json

        sleep 0.1

        # ensure the trigger has fired
        state.triggered.should be_true

        compare2 = Trigger::Conditions::Comparison.new(
          left: "hello",
          operator: "equal",
          right: {
            mod:    "Test_1",
            status: "greeting",
            keys:   [] of String,
          }
        )

        trigger.conditions.try &.comparisons = [compare, compare2]
        trigger.conditions_will_change!
        trigger.save!

        sleep 0.1

        # The state is replaced with a new state on update
        state = ::LOADER.instances[inst.id]
        state.triggered.should be_false
        store[:greeting] = "hello".to_json

        sleep 0.1

        state.triggered.should be_true

        func = Trigger::Actions::Function.new(
          mod: "Test_1",
          method: "start"
        )

        # ensure module metadata exists
        meta = PlaceOS::Driver::DriverModel::Metadata.new({
          "start" => {} of String => Array(JSON::Any),
        }, ["Functoids"])
        redis.set("interface/mod-1234", meta.to_json)

        # mock out the exec request
        WebMock.stub(:post, "http://127.0.0.1:9001/api/core/v1/command/mod-1234/execute")
          .with(body: "{\"__exec__\":\"start\",\"start\":{}}")
          .to_return(body: "null")

        trigger.actions.try &.functions = [func]
        trigger.actions_will_change!
        trigger.save!

        sleep 0.1

        # Check the state in redis
        inst_store = PlaceOS::Driver::Storage.new(inst.id.not_nil!)
        status = JSON.parse(inst_store["state"])
        status["triggered"].as_bool.should be_true
        status["trigger_count"].as_i.should eq(1)
        status["action_errors"].as_i.should eq(0)
        status["comparison_errors"].as_i.should eq(0)
      end # with_redis
    end   # it
  end     # describe
end       # module
