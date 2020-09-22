require "./state"

class PlaceOS::Triggers::State::Comparison
  Log = ::App::Log.for("comparison")

  def initialize(
    @state : State,
    @condition_key : String,
    @system_id : String,
    left : PlaceOS::Model::Trigger::Conditions::Comparison::Value,
    @compare : String,
    right : PlaceOS::Model::Trigger::Conditions::Comparison::Value
  )
    @left = case left
            when PlaceOS::Model::Trigger::Conditions::Comparison::Constant
              Constant.new(left)
            when PlaceOS::Model::Trigger::Conditions::Comparison::StatusVariable
              Status.new(left)
            else
              raise "unsupported comparison type"
            end

    @right = case right
             when PlaceOS::Model::Trigger::Conditions::Comparison::Constant
               Constant.new(right)
             when PlaceOS::Model::Trigger::Conditions::Comparison::StatusVariable
               Status.new(right)
             else
               raise "unsupported comparison type"
             end
  end

  property left : Constant
  property compare : String
  property right : Constant

  def bind!(subscriptions) : Nil
    left.bind!(self, subscriptions, @system_id)
    right.bind!(self, subscriptions, @system_id)
    nil
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def compare!
    left_val = @left.value
    right_val = @right.value

    result = case compare
             when "equal"
               left_val == right_val
             when "not_equal"
               left_val != right_val
             when "greater_than"
               left_val.as(Float64 | Int64) > right_val.as(Float64 | Int64)
             when "greater_than_or_equal"
               left_val.as(Float64 | Int64) >= right_val.as(Float64 | Int64)
             when "less_than"
               left_val.as(Float64 | Int64) < right_val.as(Float64 | Int64)
             when "less_than_or_equal"
               left_val.as(Float64 | Int64) <= right_val.as(Float64 | Int64)
             when "and"
               left_val != false && right_val != false && !left_val.nil? && !right_val.nil?
             when "or"
               (left_val != false && !left_val.nil?) || (right_val != false && !right_val.nil?)
             when "exclusive_or"
               if left_val != false && right_val != false && !left_val.nil? && !right_val.nil?
                 false
               else
                 (left_val != false && !left_val.nil?) || (right_val != false && !right_val.nil?)
               end
             else
               false
             end

    Log.debug { {
      message:   "comparing #{left_val.inspect} #{compare} #{right_val.inspect} == #{result}",
      system_id: @system_id,
    } }

    @state.set_condition @condition_key, result
  rescue error
    @state.set_condition @condition_key, false
    @state.increment_comparison_error
    Log.warn(exception: error) { {
      message:   "comparing #{@left.value.inspect} #{@compare} #{@right.value.inspect}",
      system_id: @system_id,
    } }
  end

  class Constant
    def initialize(
      @value : JSON::Any::Type
    )
    end

    getter value

    def bind!(comparison, subscriptions, system_id) : Nil
    end
  end

  class Status < Constant
    def initialize(
      @status : PlaceOS::Model::Trigger::Conditions::Comparison::StatusVariable
    )
      @value = nil
    end

    @value : JSON::Any::Type

    def bind!(comparison, subscriptions, system_id)
      module_name, index = PlaceOS::Driver::Proxy::RemoteDriver.get_parts(@status[:mod])

      Log.debug { {
        system_id: system_id,
        module:    module_name,
        index:     index,
        status:    @status[:status],
        message:   "subscribed to '#{@status[:status]}'",
      } }

      subscriptions.subscribe(system_id, module_name, index, @status[:status]) do |_, data|
        val = JSON.parse(data)

        Log.debug { {
          system_id: system_id,
          module:    module_name,
          index:     index,
          status:    @status[:status],
          message:   "received value for comparison: #{data}",
        } }

        # Grab the deeper key if specified
        final_index = @status[:keys].size - 1
        @status[:keys].each_with_index do |key, inner_index|
          break if val.raw.nil?

          next_val = val[key]?
          if next_val
            case next_val.raw
            when Hash
              val = next_val
            else
              if final_index == inner_index
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

        Log.debug { {
          system_id: system_id,
          module:    module_name,
          index:     index,
          status:    @status[:status],
          message:   "dug for #{@status[:keys]} - got #{val.inspect}",
        } }

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
