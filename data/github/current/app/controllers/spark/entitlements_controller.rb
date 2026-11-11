# typed: true
# frozen_string_literal: true

class Spark::EntitlementsController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Collab,
  ApplicationRecord::Configurations,
  ApplicationRecord::Copilot,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Ballast, # temporary, for free cca experiment

  def show
    copilot_result = { licenseType: helpers.license_type }
    copilot_quotas = helpers.user_quotas
    copilot_result[:quotas] = copilot_quotas if copilot_quotas
    copilot_plan = helpers.user_plan
    copilot_result[:plan] = copilot_plan if copilot_plan

    codespaces_access_checker = Codespaces::Access::SparkWorkbenchUsageChecker.new(current_user)
    codespaces_compute_result = {
      allowed: codespaces_access_checker.perform.allowed?,
      quotas: codespaces_access_checker.user_quotas,
    }

    codespaces_concurrency_policy = Codespaces::SparkWorkbenchConcurrencyPolicy.new(current_user, billable_owner: current_user)
    codespaces_sessions_result = {
      allowed: codespaces_concurrency_policy.has_capacity?,
    }

    result = {
      copilot: copilot_result,
      codespaces_compute: codespaces_compute_result,
      codespaces_sessions: codespaces_sessions_result,
      billing_status: get_billing_status,
      user_status: check_user_permissions,
    }

    render json: result
  end

  private

  # Available statuses and docs can be found here: https://github.com/github/billing-platform/blob/main/docs/reference/features/can-proceed-with-usage.md#can-proceed-statuses
  CanProceedWithUsageResponse = T.type_alias do
    {
      canProceed: T::Boolean,
      status: String,
    }
  end

  sig { returns(CanProceedWithUsageResponse) }
  def get_billing_status
    if !copilot_user.provider_customer_id
      if copilot_user.copilot_provider.present?
        return { canProceed: false, status: "MissingCustomer" }
      else
        return { canProceed: true, status: "UsageAllowed" }
      end
    end

    entity_detail = {
      customerId: copilot_user.provider_customer_id.to_s,
      actorId: copilot_user.user.id,
    }
    if copilot_user.copilot_provider.present? && copilot_user.copilot_provider.is_a?(::Copilot::Organization)
      entity_detail[:ownerId] = copilot_user.copilot_provider.id
    end
    cpwu_response = billing_platform_client.can_proceed_with_usage(
      usage_key: {
        sku: "spark_premium_request",
        product: "spark",
        entityDetail: entity_detail,
      },
    )

    if cpwu_response.is_a?(Billing::Platform::Api::Error)
      Failbot.report(cpwu_response)
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/can_proceed_with_usage"])
      # CPWU should fail open - If we can't reach the BP then assume users can proceed
      { canProceed: true, status: "UsageAllowed" }
    else
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/can_proceed_with_usage"])
      { canProceed: cpwu_response[:canProceed], status: cpwu_response[:status] }
    end
  end

  sig { returns(Copilot::Public::User) }
  def copilot_user
    ::Copilot::Public::User.new(current_user)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def check_user_permissions
    copilot_user = ::Copilot::Public::User.new(current_user)
    copilot_provider = copilot_user.copilot_provider
    url = nil

    if copilot_user.copilot_provider.is_a?(::Copilot::Business)
      url = settings_billing_enterprise_path(copilot_provider)
    elsif copilot_user.copilot_provider.is_a?(::Copilot::Organization)
      url = settings_org_billing_url(copilot_provider)
    end

    {
      admin: !!copilot_user.copilot_provider&.admins&.exists?(current_user.id),
      billingUrl: url,
      type: copilot_user.copilot_provider&.configurable_object&.class&.to_s,
    }
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end
end
