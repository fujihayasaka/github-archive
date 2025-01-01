# typed: true
# frozen_string_literal: true

module User::SparkFeatureDependency
  include GitHub::Memoizer
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  # Determines if the user has Spark enabled. A user is enabled if they're a part of the Spark rollout and have Spark
  # enabled via policy.
  sig { returns(T::Boolean) }
  def spark_enabled?
    return false if unsupported_spark_emu_account?
    return true if feature_enabled_globally_or_for_user?(feature_name: :copilot_workbench, subject: self)
    return true if feature_enabled_globally_or_for_user?(feature_name: :github_spark, subject: self)
    return false unless copilot_user

    part_of_ce_rollout? && spark_policy_enabled? ||
    part_of_cb_rollout? && spark_policy_enabled? ||
    part_of_cs_rollout_with_policy_enabled? ||
    part_of_pro_plus_rollout? ||
    part_of_pro_rollout? ||
    part_of_limited_rollout?
  end

  # Determines if the user is managed by an enterprise not yet supported for Spark use.
  sig { returns(T::Boolean) }
  def unsupported_spark_emu_account?
    return false unless self.is_enterprise_managed?

    self.enterprise_managed_business&.shortcode != "microsoft"
  end

  # Determines if the user is part of the Spark rollout. This is separate from Spark access because a user can be part
  # of the rollout, but not have Spark enabled due to an org/enterprise revoking access.
  sig { returns(T::Boolean) }
  def part_of_spark_rollout?
    return true if feature_enabled_globally_or_for_user?(feature_name: :copilot_workbench, subject: self)
    return true if feature_enabled_globally_or_for_user?(feature_name: :github_spark, subject: self)
    return false unless copilot_user

    part_of_ce_rollout? ||
    part_of_cb_rollout? ||
    part_of_cs_rollout? ||
    part_of_pro_plus_rollout? ||
    part_of_pro_rollout? ||
    part_of_limited_rollout?
  end

  private

  memoize def copilot_user
    T.bind(self, User)
    Copilot::User.new(self)
  end

  memoize def part_of_ce_rollout?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_ce_rollout, subject: self) && copilot_user.has_ce_access?
  end

  memoize def part_of_cb_rollout?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_cb_rollout, subject: self) &&
      copilot_user.has_cb_access? && !copilot_user.has_ce_access?
  end

  memoize def part_of_cs_rollout?
    # Spark is not currently supported for enterprise managed users.
    return false if self.is_enterprise_managed?

    feature_enabled_globally_or_for_user?(feature_name: :copilot_cs_rollout, subject: self) &&
      copilot_user.has_copilot_standalone_business?
  end

  memoize def part_of_cs_rollout_with_policy_enabled?
    return false unless part_of_cs_rollout?

    spark_policy_enabled?(standalone: true)
  end

  memoize def part_of_pro_plus_rollout?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_pro_plus_rollout, subject: self) &&
      copilot_user.has_pro_plus_access?
  end

  memoize def part_of_pro_rollout?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_pro_rollout, subject: self) &&
      copilot_user.has_pro_access?
  end

  memoize def part_of_limited_rollout?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_limited_rollout, subject: self) &&
      copilot_user.has_limited_access?
  end

  # Determines which policy to use for enabling Spark, then returns whether or not Spark is enabled for the user.
  sig { params(standalone: T::Boolean).returns(T::Boolean) }
  def spark_policy_enabled?(standalone: false)
    if feature_enabled_globally_or_for_user?(feature_name: :spark_access_copilot_policy, subject: self)
      # Delegate to Copilot::User#spark_enabled?
      copilot_user.spark_enabled?
    else
      # The user must belong to a business with the Copilot beta features enabled.
      copilot_user.copilot_businesses.any? do |copilot_business|
        next if standalone && !copilot_business.copilot_standalone?
        copilot_business.beta_features_github_chat_enabled?
      end
    end
  end
end
