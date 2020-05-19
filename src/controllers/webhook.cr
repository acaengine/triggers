module PlaceOS::Triggers::Api
  class Webhook < Application
    base "/api/triggers/v2/webhook"

    before_action :find_hook

    @trigger : Model::TriggerInstance?

    class WebhookParams < ActiveModel::Model
      include ActiveModel::Validation

      attribute id : String
      attribute secret : String

      validates :id, presence: true
      validates :secret, presence: true

      def validate!
        raise "missing trigger id or secret params" unless self.valid?
        self
      end
    end

    # Return 204 if the state isn't loaded, might still be loading?
    # 202 on success
    def create
      trig = @trigger.not_nil!
      trigger_id = trig.id
      if state = LOADER.instances[trigger_id]?
        Log.debug { {
          message:   "setting webhook condition for '#{state.trigger.name}'",
          instance:  trigger_id,
          trigger:   trig.trigger_id,
          system_id: trig.control_system_id,
        } }
        state.temporary_condition_met("webhook")
        head :accepted
      else
        Log.warn { {
          message:   "trigger state not loaded",
          instance:  trigger_id,
          trigger:   trig.trigger_id,
          system_id: trig.control_system_id,
        } }
        head :no_content
      end
    end

    def find_hook
      # Find will raise a 404 (not found) if there is an error
      args = WebhookParams.new(params).validate!
      trig = Model::TriggerInstance.find!(args.id.not_nil!)

      # Determine the validity of loaded TriggerInstance
      if trig.enabled
        if trig.webhook_secret == args.secret
          @trigger = trig
        else
          Log.warn { {
            message:   "incorrect secret for trigger instance #{args.id}",
            instance:  args.id,
            trigger:   trig.trigger_id,
            system_id: trig.control_system_id,
          } }
          head :not_found
        end
      else
        Log.warn { {
          message:   "webhook for disabled trigger instance #{args.id}",
          instance:  args.id,
          trigger:   trig.trigger_id,
          system_id: trig.control_system_id,
        } }
        head :not_found
      end
    end
  end
end
