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
    copilot_user = current_copilot_user_v2
    return false unless copilot_user

    copilot_user.generated_commit_message_enabled? && copilot_generate_commit_message_allowed_for_repo?(branch_name)
  end

  sig { returns(T::Boolean) }
  memoize def copilot_generate_commit_message_disabled?
    FeatureFlag.vexi.enabled?("copilot_generate_commit_message_disabled", current_user, default: false)
  end

  sig { params(branch_name: String).returns(T::Boolean) }
  def copilot_generate_commit_message_allowed_for_repo?(branch_name)
    # Disable the feature if commit message pattern restrictions are enabled for the branch the user is currently on
    branch_rules = BranchRuleEvaluator.for_repository_with_branch_name(T.must(current_repository), branch_name)

    return true unless branch_rules

    !branch_rules.commit_message_pattern_restriction_enabled?(current_user)
  end
end
