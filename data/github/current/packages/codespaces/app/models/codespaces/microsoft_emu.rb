
# typed: true
# frozen_string_literal: true

# We want to allow creation of codespaces for the github/spark-template repo
# by users in the Microsoft EMU (*_microsoft), but the enterprise settings
# don't allow that. We're willing given the timing to just set the billable owner
# when all this flagging passes to a known MSFT org and move on.
module Codespaces
  module MicrosoftEmu
    # We have to assign the token to some org within the Enterprise. This is the most
    # common one with more than 200k members, so we chose it.
    DEFAULT_ORG = "ms-copilot"

    sig do
      params(
        user: User,
        repository: T.nilable(Repository),
      ).returns(T::Boolean)
    end
    def self.is_spark_for_microsoft_emu?(user, repository)
      return false unless user.feature_flag_enabled_or_raise?(:copilot_workbench_microsoft_emu) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      in_microsoft_emu = user.is_enterprise_managed? &&
        user.enterprise_managed_business.present? &&
        user.enterprise_managed_business.shortcode == "microsoft"

      # We're a Spark repo if either we're the spark-template itself (unpublished)
      # or if we're a repo that was published from spark-template
      is_spark_repo = repository&.name_with_display_owner == "github/spark-template" ||
        repository&.template_repository&.name_with_display_owner == "github/spark-template"

      in_microsoft_emu && is_spark_repo
    end
  end
end
