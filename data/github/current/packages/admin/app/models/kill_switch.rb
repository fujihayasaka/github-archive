# typed: strict
# frozen_string_literal: true

# Public: A way to stop features from happening for certain organizations or businesses.
# This is used if a workload can cause problems in a production environment and needs to be shut off by feature flag
# only for specific organizations or businesses.
module KillSwitch
  extend T::Sig
  extend ActiveSupport::Concern

  FEATURE_FLAG = "bypass_heavy_workloads"

  # Public: Is the kill switch enabled for the selected org or business?
  sig do
    params(
      workload_name: String,
      log_fields: T::Hash[String, T.untyped]
    ).returns(T::Boolean)
  end
  def kill_switch_enabled?(workload_name, log_fields: {})
    # If a workload is causing problems in production, getting a fix in quickly means not updating tests for each test
    # that calls the function. Therefore TEST_ALL_FEATURES should be skipped.
    return false if Rails.env.test? && TestEnv.test_all_features? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    return false if GitHub.single_business_environment?

    case self
    when Organization
      log_fields = log_fields.merge("gh.organization.id" => self.id)
      if business = self.business
        return true if business.kill_switch_enabled?(workload_name, log_fields: log_fields)
      end
    when Business
      log_fields = log_fields.merge("gh.business.id" => self.id)
    else
      return false
    end

    return false unless self.feature_enabled?(FEATURE_FLAG)
    instrument_kill_switch(workload_name, log_fields)

    true
  end

  private

  sig do
    params(
      workload_name: String,
      log_fields: T::Hash[String, T.untyped]
    ).void
  end
  def instrument_kill_switch(workload_name, log_fields)
    GitHub.logger.error({
      "exception.type" => "KillSwitch",
      "exception.message" => "Workload skipped due to #{FEATURE_FLAG} flag",
      "workload" => workload_name,
    }.merge(log_fields))
  end
end
