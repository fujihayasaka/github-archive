# typed: true
# frozen_string_literal: true

class Api::ThirdParty::Mailchimp < Api::ThirdParty

  before do
    deliver_error!(404) unless GitHub.mailchimp_enabled?
  end

  # Webhook documentation:
  #   http://kb.mailchimp.com/integrations/other-integrations/how-to-set-up-webhooks
  # Webhook source:
  #   https://us11.admin.mailchimp.com/lists/tools/webhooks?id=257769
  get "/third-party/mailchimp/webhook", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/marketing-operations"
    validate_mailchimp_key!

    deliver_empty status: 204
  end

  # Webhook documentation:
  #   http://kb.mailchimp.com/integrations/other-integrations/how-to-set-up-webhooks
  # Webhook source:
  #   https://us11.admin.mailchimp.com/lists/tools/webhooks?id=257769
  post "/third-party/mailchimp/webhook", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/marketing-operations"
    validate_mailchimp_key!

    form_data = receive_form_encoded

    data          = form_data[:data] || {}
    type          = form_data[:type]
    email_address = data[:email]

    MailchimpWebhookJob.perform_later(type, email_address, data)
    deliver_empty status: 202
  end

  private

  def receive_form_encoded
    Rack::Utils.parse_nested_query(request.body.read).with_indifferent_access
  end

  def validate_mailchimp_key!
    deliver_error!(404) unless key = params[:key].presence
    webhook_key = GitHub::Config::Mailchimp.webhook_key
    deliver_error!(404) unless SecurityUtils.secure_compare(key, webhook_key)
  end
end
