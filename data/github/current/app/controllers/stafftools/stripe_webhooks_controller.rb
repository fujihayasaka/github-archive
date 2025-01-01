# typed: true
# frozen_string_literal: true

class Stafftools::StripeWebhooksController < StafftoolsController
  before_action :ensure_billing_enabled
  before_action :lookup_webhook, only: [:ignore, :perform]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    @webhooks = ::Billing::StripeWebhook.pending.ignoring_recent.order(:created_at)
    render "stafftools/stripe_webhooks/index", locals: { webhooks: @webhooks }
  end

  def ignore # rubocop:todo GitHub/UseRestfulActions
    @webhook.ignored!
    flash[:success] = "Webhook id #{@webhook.id} permanently ignored"
    redirect_back(fallback_location: "stafftools/stripe_webhooks")
  end

  def perform # rubocop:todo GitHub/UseRestfulActions
    begin
      @webhook.perform
      flash[:success] = "Webhook id #{@webhook.id} successfully processed"
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e, "gh.billing.stripe_webhook.id": @webhook.id)
      flash[:error] = e
    ensure
      redirect_back(fallback_location: "stafftools/stripe_webhooks")
    end
  end

  private

  def lookup_webhook
    @webhook = ::Billing::StripeWebhook.find(params[:stripe_webhook_id])
  rescue ActiveRecord::RecordNotFound => e
    Failbot.report(e, "gh.billing.stripe_webhook.id": params[:stripe_webhook_id])
    flash[:error] = e
    redirect_back(fallback_location: "stafftools/stripe_webhooks")
  end
end
