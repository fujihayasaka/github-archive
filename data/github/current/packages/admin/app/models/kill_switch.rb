# typed: strict
# frozen_string_literal: true

# Public: A way to stop features from happening for certain organizations or businesses.
# This is used if a workload can cause problems in a production environment and needs to be shut off by feature flag
# only for specific organizations or businesses.
module KillSwitch
  extend ActiveSupport::Concern

  FEATURE_FLAG = "bypass_heavy_workloads"
  FEATURE_FLAG_TTL = T.let(1.minute, ActiveSupport::Duration)

  class KillSwitchError < StandardError; end

  sig { returns(T::Hash[Symbol, Time]) }
  private def last_vexi_cleared_by_ff
    @last_vexi_cleared_by_ff ||= T.let(Hash.new { |h, k| h[k] = Time.current.utc }, T.nilable(T::Hash[Symbol, Time]))
  end

  # Public: Is the kill switch enabled for the selected org or business?
  sig do
    params(
      workload_name: String,
      feature_flag: T.any(String, Symbol),
      log_fields: T::Hash[String, T.untyped]
    ).returns(T::Boolean)
  end
  def kill_switch_enabled?(workload_name, feature_flag: FEATURE_FLAG, log_fields: {})
    async_kill_switch_enabled?(workload_name, feature_flag: feature_flag, log_fields: log_fields).sync
  end

  # Public: Async version - Is the kill switch enabled for the selected org or business?
  sig do
    params(
      workload_name: String,
      feature_flag: T.any(String, Symbol),
      log_fields: T::Hash[String, T.untyped]
    ).returns(Promise[T::Boolean])
  end
  def async_kill_switch_enabled?(workload_name, feature_flag: FEATURE_FLAG, log_fields: {})
    # If a workload is causing problems in production, getting a fix in quickly means not updating tests for each test
    # that calls the function. Therefore TEST_ALL_FEATURES should be skipped.
    return Promise.resolve(T.let(false, T::Boolean)) if Rails.env.test? && TestEnv.test_all_features? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    return Promise.resolve(T.let(false, T::Boolean)) if GitHub.single_business_environment?

    case self
    when Organization
      log_fields = log_fields.merge("gh.organization.id" => self.id)
      async_business.then do |business|
        if business
          business_log_fields = log_fields.merge("gh.business.id" => business.id)
          # Check business first, then org if business doesn't have kill switch enabled
          if feature_flag_kill_switch_enabled?(business, workload_name, feature_flag, business_log_fields)
            true
          else
            feature_flag_kill_switch_enabled?(self, workload_name, feature_flag, log_fields)
          end
        else
          feature_flag_kill_switch_enabled?(self, workload_name, feature_flag, log_fields)
        end
      end
    when Business
      log_fields = log_fields.merge("gh.business.id" => self.id)
      Promise.resolve(feature_flag_kill_switch_enabled?(self, workload_name, feature_flag, log_fields))
    else
      Promise.resolve(T.let(false, T::Boolean))
    end
  end

  sig do
    params(
      workload_name: String,
      feature_flag: T.any(String, Symbol),
      log_fields: T::Hash[String, T.untyped]
    ).void
  end
  def raise_if_kill_switch_enabled!(workload_name, feature_flag: FEATURE_FLAG, log_fields: {})
    if kill_switch_enabled?(workload_name, feature_flag:, log_fields:)
      Kernel.raise KillSwitchError, "Workload skipped due to #{feature_flag} flag"
    end
  end

  private

  # Private: Check if the feature flag is enabled for the kill switch on the given object.
  # This checks the feature flag directly on the provided object (Organization or Business)
  # without checking parent Business relationships.
  sig do
    params(
      object: T.any(Organization, Business),
      workload_name: String,
      feature_flag: T.any(String, Symbol),
      log_fields: T::Hash[String, T.untyped]
    ).returns(T::Boolean)
  end
  def feature_flag_kill_switch_enabled?(object, workload_name, feature_flag, log_fields)
    if T.must(last_vexi_cleared_by_ff[feature_flag.to_sym]) < FEATURE_FLAG_TTL.ago
      FeatureFlag.vexi.clear_feature_flag_memoization(feature_flag)
      last_vexi_cleared_by_ff[feature_flag.to_sym] = Time.current.utc
    end

    return false unless T.unsafe(object).feature_flag_enabled?(feature_flag, default: false, memoize: false)
    instrument_kill_switch(workload_name, feature_flag, log_fields)

    true
  end

  sig do
    params(
      workload_name: String,
      feature_flag: T.any(String, Symbol),
      log_fields: T::Hash[String, T.untyped]
    ).void
  end
  def instrument_kill_switch(workload_name, feature_flag, log_fields)
    GitHub.logger.error({
      "exception.type" => "KillSwitch",
      "exception.message" => "Workload skipped due to #{feature_flag} flag",
      "workload" => workload_name,
    }.merge(log_fields))
  end
end
