# typed: strict
# frozen_string_literal: true

class Zuora::WebhooksController < ApplicationController

  include ApplicationController::JsonDependency
  include GitHub::RateLimitedRequest

  rate_limit_requests except: :create

  if Rails.env.development? && ENV["CODESPACES"]
    skip_before_action :basic_auth_for_public_forwarded_ports, only: :create
  end

  # CAP is not required, this controller does not access org/business data
  skip_before_action :perform_conditional_access_checks, only: [:create] # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :parse_json_params
  before_action :authenticate
  before_action :filter_by_stamp

  sig { void }
  def create
    Billing::ZuoraWebhook.receive(payload)

    head :ok
  end

  private

  sig { returns(T::Boolean) }
  def verify_authenticity_token?
    false
  end

  sig { void }
  def authenticate
    authenticate_or_request_with_http_basic do |username, password|
      correct_username = Rack::Utils.secure_compare(username, GitHub.zuora_webhook_username)

      old_password_correct = GitHub.zuora_webhook_password.present? &&
        Rack::Utils.secure_compare(password, GitHub.zuora_webhook_password)

      new_password_correct = GitHub.zuora_webhook_new_password.present? &&
        Rack::Utils.secure_compare(password, GitHub.zuora_webhook_new_password)

      if old_password_correct && (GitHub.zuora_webhook_new_password.present? && !new_password_correct)
        GitHub.dogstats.increment("zuora.webhook.old_password_used")
      end

      correct_password = old_password_correct || new_password_correct

      correct_username && correct_password
    end
  end

  sig { void }
  def filter_by_stamp
    current_stamp = GitHub::Config::Proxima.current_stamp_or_dotcom
    # we only allow a webhook without a stamp to be processed in dotcom. proxima webhooks should always have a stamp value.
    return if payload["stamp"].blank? && current_stamp == "dotcom"

    webhook_stamp = payload["stamp"]
    if current_stamp != webhook_stamp
      GitHub.dogstats.increment("zuora.webhook.stamp_mismatch.count", tags: ["webhook_stamp:#{webhook_stamp}"])
      account_id = payload.fetch("account_id", "")
      subscription_id = payload.fetch("subscription_id", "")
      GitHub.logger.error("Zuora webhook stamp mismatch", "code.namespace" => self.class.name, "code.function" => __method__, "zuora.webhook.stamp" => webhook_stamp, "zuora.account.id" => account_id, "zuora.subscription.id" => subscription_id)
      head :forbidden
    end
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def payload
    params.except(:action, :controller).permit!.to_h
  end
end
