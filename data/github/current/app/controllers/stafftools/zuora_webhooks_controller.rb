# typed: true
# frozen_string_literal: true

class Stafftools::ZuoraWebhooksController < StafftoolsController
  before_action :ensure_billing_enabled
  before_action :lookup_webhook, except: [:index, :retry_all]

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

  PER_PAGE = 20

  def index
    @show_status = params[:webhook_type]&.titleize || "All"
    @webhooks = ::Billing::ZuoraWebhook
      .where(status: [:pending, :investigating])
      .ignoring_recent
      .order(:created_at)

    if @show_status == "Invoiced"
      @webhooks = @webhooks.invoiced
    elsif @show_status == "Pending"
      @webhooks = @webhooks.pending
    elsif @show_status == "Investigating"
      @webhooks = @webhooks.investigating
    end

    @webhooks = @webhooks.paginate(
      page: current_page,
      per_page: PER_PAGE
    )

    render "stafftools/zuora_webhooks/index", locals: { webhooks: @webhooks, show_status: @show_status }
  end

  def retry_all # rubocop:todo GitHub/UseRestfulActions
    webhooks = ::Billing::ZuoraWebhook.pending.ignoring_recent
    Zuora::WebhooksFanoutJob.perform_later

    flash[:notice] = "#{webhooks.count} webhooks have been scheduled to be retried."
    redirect_back(fallback_location: "stafftools/zuora_webhooks")
  end

  def ignore # rubocop:todo GitHub/UseRestfulActions
    @webhook.ignored!
    flash[:notice] = "Webhook id #{@webhook.id} permanently ignored"
    redirect_back(fallback_location: "stafftools/zuora_webhooks")
  end

  def investigate # rubocop:todo GitHub/UseRestfulActions
    begin
      @webhook.update!(status: :investigating, investigation_notes: params[:investigation_notes])
      flash[:notice] = "Webhook id #{@webhook.id} marked as being investigated"
    rescue ActiveRecord::RecordInvalid => e
      flash[:error] = e.message
    ensure
      redirect_back(fallback_location: "stafftools/zuora_webhooks")
    end
  end

  def perform # rubocop:todo GitHub/UseRestfulActions
    begin
      @webhook.perform
      flash[:notice] = "Webhook id #{@webhook.id} successfully processed"
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      Failbot.report(e, "gh.billing.zuora.webhook_id": @webhook.id)
      flash[:error] = e
    ensure
      redirect_back(fallback_location: "stafftools/zuora_webhooks")
    end
  end

  private

  def lookup_webhook
    @webhook = ::Billing::ZuoraWebhook.find(params[:zuora_webhook_id])
  rescue ActiveRecord::RecordNotFound => e
    Failbot.report(e, "gh.billing.zuora.webhook_id": params[:zuora_webhook_id])
    flash[:error] = e
    redirect_back(fallback_location: "stafftools/zuora_webhooks")
  end
end
