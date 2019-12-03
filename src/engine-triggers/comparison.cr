require "./state"

class ACAEngine::Triggers::State::Comparison
  def initialize(
    @state : State,
    @condition_key : String,
    @system_id : String,
    left : ACAEngine::Model::Trigger::Conditions::Comparison::Value,
    @compare : String,
    right : ACAEngine::Model::Trigger::Conditions::Comparison::Value
  )
    @left = case left
            when ACAEngine::Model::Trigger::Conditions::Comparison::Constant
              Constant.new(left)
            when ACAEngine::Model::Trigger::Conditions::Comparison::StatusVariable
              Status.new(left)
            else
              raise "unsupported comparison type"
            end

    @right = case right
             when ACAEngine::Model::Trigger::Conditions::Comparison::Constant
               Constant.new(right)
             when ACAEngine::Model::Trigger::Conditions::Comparison::StatusVariable
               Status.new(right)
             else
               raise "unsupported comparison type"
             end
  end

  property left : Constant
  property compare : String
  property right : Constant

  def bind!(subscriptions)
    left.bind!(self, subscriptions, @system_id)
    right.bind!(self, subscriptions, @system_id)
    nil
  end

  def compare!
    left_val = @left.value
    right_val = @right.value
    result = case compare
             when "equal"
               left_val == right_val
             when "not_equal"
               left_val != right_val
             when "greater_than"
               left_val > right_val
             when "greater_than_or_equal"
               left_val >= right_val
             when "less_than"
               left_val < right_val
             when "less_than_or_equal"
               left_val <= right_val
             when "and"
               left_val && right_val
             when "or"
               !!(left_val || right_val)
             when "exclusive_or"
               (!!(left_val || right_val)) && !(left_val && right_val)
             else
               false
             end

    @state.set_condition @condition_key, result
  end

  class Constant
    def initialize(
      @value : JSON::Any::Type
    )
    end

    getter value

    def bind!(comparison, subscriptions, system_id)
      nil
    end
  end

  class Status < Constant
    def initialize(
      @status : ACAEngine::Model::Trigger::Conditions::Comparison::StatusVariable
    )
      @value = nil
    end

    @value : JSON::Any::Type

    def bind!(comparison, subscriptions, system_id)
      module_name, index = ACAEngine::Driver::Proxy::RemoteDriver.get_parts(@status.mod)
      subscriptions.subscribe(system_id, module_name, index, @status.status) do |_, data|
        val = JSON.parse(data)

        # Grab the deeper key if specified
        final_index = @status.keys.size - 1
        @status.keys.each_with_index do |key, index|
          next_val = val[key]?
          if next_val
            case temp = next_val.raw
            when Hash
              val = next_val
            else
              if final_index == index
                val = next_val
              else
                # There are more keys and we don't have a hash to go deeper
                val = nil
                break
              end
            end
          else
            val = nil
            break
          end
        end

        # Update the value and re-compare
        if val
          @value = val.raw
        else
          @value = nil
        end
        comparison.compare!
      end
      nil
    end

    getter value
  end
end
