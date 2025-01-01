# typed: true
# frozen_string_literal: true

module CopilotGenerateCommitMessageHelper
  extend T::Helpers
  include CopilotAuthHelper
  include GitHub::Memoizer
  include GitHub::ResilienceMixin

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
  def current_copilot_user_v2; end

  sig { abstract.returns(T.nilable(::Repository)) }
  def current_repository; end

  sig { params(branch_name: String).returns(T::Boolean) }
  def copilot_generate_commit_message_allowed?(branch_name)
    return false unless current_copilot_user_v2

    copilot_generate_commit_message_allowed_for_user? &&
      copilot_generate_commit_message_allowed_for_org? &&
      copilot_generate_commit_message_allowed_for_repo?(branch_name)
  end

  # Allowed on any copilot plan and respects settings
  sig { returns(T::Boolean) }
  memoize def copilot_generate_commit_message_allowed_for_user?
    return false unless current_copilot_user_v2

    with_database_error_fallback(fallback: false) do
      T.must(current_copilot_user_v2).has_copilot_access? &&
        T.must(current_copilot_user_v2).show_copilot_functionality? &&
        copilot_policy_enabled_for_user?
    end
  end

  # Allowed on public repos regardless of org settings, and on private repos if the org has copilot enabled
  sig { returns(T::Boolean) }
  memoize def copilot_generate_commit_message_allowed_for_org?
    return true if T.must(current_repository).public?
    return true unless T.must(current_repository).organization

    copilot_organization = Copilot::Organization.new(T.must(T.must(current_repository).organization))

    with_database_error_fallback(fallback: false) do
      copilot_organization.copilot_enabled? &&
      copilot_policy_enabled_for_organization?(copilot_organization)
    end
  end

  sig { returns(T::Boolean) }
  memoize def copilot_generate_commit_message_enabled_for_user?
    FeatureFlag.vexi.enabled?("copilot_generate_commit_message_blob", current_user, default: false)
  end

  sig { returns(T::Boolean) }
  memoize def copilot_generate_commit_message_public_preview_enabled_for_user?
    FeatureFlag.vexi.enabled?("copilot_generate_commit_message_blob_public_preview", current_user, default: false)
  end

  sig { params(branch_name: String).returns(T::Boolean) }
  def copilot_generate_commit_message_allowed_for_repo?(branch_name)
    # Disable the feature if commit message pattern restrictions are enabled for the branch the user is currently on
    branch_rules = BranchRuleEvaluator.for_repository_with_branch_name(T.must(current_repository), branch_name)

    return true unless branch_rules

    !branch_rules.commit_message_pattern_restriction_enabled?(current_user)
  end

  sig { returns(T::Boolean) }
  def cached_sku_isolation_enabled?
    FeatureFlag.vexi.enabled?("copilot_generate_commit_message_blob_cached_sku_isolation", current_user, default: false)
  end

  private

  sig { params(copilot_organization: Copilot::Organization).returns(T::Boolean) }
  def copilot_policy_enabled_for_organization?(copilot_organization)
    copilot_in_dotcom_enabled = T.let(copilot_organization.copilot_for_dotcom_enabled?, T::Boolean)

    # If we're in public preview, use beta features for GitHub Chat setting
    if copilot_generate_commit_message_public_preview_enabled_for_user?
      return copilot_in_dotcom_enabled && copilot_organization.beta_features_github_chat_enabled?
    end

    # If we're GA and the code review policy feature flag is enabled, use code review policy
    if code_review_policy_feature_flag_enabled?
      return copilot_organization.code_review_enabled?
    end

    # Otherwise, fallback to Copilot in Dotcom setting
    copilot_in_dotcom_enabled
  end

  sig { returns(T::Boolean) }
  def copilot_policy_enabled_for_user?
    copilot_user = current_copilot_user_v2
    return false unless copilot_user

    return copilot_user.beta_features_github_chat_enabled? if copilot_generate_commit_message_public_preview_enabled_for_user?
    return copilot_user.code_review_enabled? if code_review_policy_feature_flag_enabled?

    true
  end

  sig { returns(T::Boolean) }
  def code_review_policy_feature_flag_enabled?
    FeatureFlag.vexi.enabled?("copilot_generate_commit_message_use_code_review_policy", current_user, default: false)
  end
end
