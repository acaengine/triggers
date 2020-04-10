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
      if state = LOADER.instances[@trigger.not_nil!.id]?
        state.temporary_condition_met("webhook")
        head :accepted
      else
        head :no_content
      end
    end

    def find_hook
      # Find will raise a 404 (not found) if there is an error
      args = WebhookParams.new(params).validate!
      trig = Model::TriggerInstance.find!(args.id.not_nil!)

      # Determine the validity of loaded TriggerInstance
      unless trig.enabled &&
             trig.webhook_secret == args.secret
        head :not_found
      end

      @trigger = trig
    end
  end
end
