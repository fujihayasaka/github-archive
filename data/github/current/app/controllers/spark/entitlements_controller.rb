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
      billing_status: check_billing_troubles,
      user_status: check_user_permissions,
    }

    render json: result
  end

  private

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def check_billing_troubles
    personal_trouble = current_user.billing_trouble?
    org_trouble = current_user.org_billing_trouble?

    {
      personalTrouble: personal_trouble,
      orgTrouble: org_trouble,
    }
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
      type: copilot_user.copilot_provider&.type,
    }
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
