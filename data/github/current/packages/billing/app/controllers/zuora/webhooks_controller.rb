# typed: strict
# frozen_string_literal: true

class Zuora::WebhooksController < ApplicationController
  extend T::Sig

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

  sig { void }
  def create
    payload = params.except(:action, :controller).permit!.to_h
    if GitHub.flipper[:use_webhook_router].enabled?
      Billing::ZuoraWebhook.create_from_payload(payload)
    else
      Billing::ZuoraWebhook.receive(payload)
    end

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
end
