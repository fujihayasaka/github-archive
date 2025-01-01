# typed: strict
# frozen_string_literal: true

module Codespaces
  class AccessChecker
    extend T::Sig
    include GitHub::Memoizer

    sig { returns(T.nilable(::User)) }
    attr_reader :billable_owner

    sig { returns(T.any(Codespaces::Access::CopilotWorkspaceBillingChecker, Codespaces::Access::MeuseBillingChecker, Codespaces::Access::VNextBillingChecker)) }
    attr_reader :billing_access_checker

    sig { returns(T.nilable(::User)) }
    attr_reader :user

    sig { returns(T.nilable(Repository)) }
    attr_reader :repository
    # We sometimes omit the repository and/or user when we don't have them, like any time we're checking about
    # an org's budget more broadly without a specific user/repository.

    sig { returns(T::Boolean) }
    attr_reader :fast_timeout

    sig { params(codespace: Codespace, fast_timeout: T::Boolean).returns(AccessChecker) }
    def self.from_codespace(codespace, fast_timeout: true)
      new(codespace.billable_owner, user: codespace.owner, repository: codespace.repository, fast_timeout:, copilot_workspace: codespace.copilot_workspace?)
    end

    # Meuse being overloaded can lead to timeouts when making requests for usage checks.
    # We should timeout relatively quickly on any request made that is time senstive, like not a background job.
    sig { params(billable_owner: T.nilable(::User), user: T.nilable(::User), repository: T.nilable(Repository), fast_timeout: T::Boolean, copilot_workspace: T::Boolean).void }
    def initialize(billable_owner, user: nil, repository: nil, fast_timeout: true, copilot_workspace: false)
      @billable_owner = billable_owner
      @user = user
      @repository = repository
      @fast_timeout = fast_timeout
      @billing_access_checker = T.let(get_billing_access_checker(fast_timeout:, copilot_workspace:), T.any(Codespaces::Access::CopilotWorkspaceBillingChecker, Codespaces::Access::MeuseBillingChecker, Codespaces::Access::VNextBillingChecker))
    end

    # Combined result of a cached check against billing's usage checker to see if the billable owner
    # can use codespaces, AND org/biz policy (as in ::PolicyGroup) checks based on specific context:
    # When a sku_name is provided, checks against machine policy.
    # When a dev_container is provided, checks against image policy.
    # Consider whether you need to run all of these checks or if allowed_by_billing is more appropriate!
    sig do
      params(
        sku_name: T.nilable(String),
        dev_container: T.nilable(Codespaces::DevContainer)
      ).returns(T::Boolean)
    end
    def allowed?(sku_name: nil, dev_container: nil)
      run_check(sku_name:, dev_container:).allowed?
    end

    # Combined result of a cached check against billing's usage checker to see if the billable owner
    # can use codespaces, and org/biz policy (as in ::PolicyGroup) checks based on specific context:
    # When a sku_name is provided, checks against machine policy.
    # When a dev_container is provided, checks against image policy.
    sig do
      params(
        sku_name: T.nilable(String),
        dev_container: T.nilable(Codespaces::DevContainer)
      ).returns(Codespaces::Access::AllowedResult)
    end
    def run_check(sku_name: nil, dev_container: nil)
      fetch_or_calculate_allowed(sku_name:, dev_container:)
    end

    # Cached check against billing's usage checker to see if the billable owner can use codespaces.
    # Does *not* run any policy checks.
    sig { returns(T::Boolean) }
    def allowed_by_billing?
      run_billing_check.allowed?
    end

    # Cached check against billing's usage checker to see if the billable owner can use codespaces.
    # Does *not* run any policy checks.
    sig { returns(Codespaces::Access::AllowedResult) }
    def run_billing_check
      fetch_or_calculate_allowed
    end

    sig { returns(Codespaces::Access::AllowedResult) }
    def calculate_prebuild_allowed
      billing_access_checker.perform(prebuild: true)
    end

    sig { returns(T::Boolean) }
    def prebuild_allowed?
      calculate_prebuild_allowed.allowed?
    end

    private

    sig { params(sku_name: T.nilable(String), dev_container: T.nilable(Codespaces::DevContainer)).returns(T.untyped) }
    def fetch_or_calculate_allowed(sku_name: nil, dev_container: nil)
      if reason = get_cached_allowed_reason
        result = Codespaces::Access::AllowedResult.new(reason)
      else
        result = billing_access_checker.perform
        cache_allowed_reason(result)
      end

      check_against_policies = result.allowed? && billable_owner.is_a?(Organization) && repository
      if check_against_policies
        result = calculate_allowed_by_policy(sku_name:, dev_container:)
      end
      result
    end

    sig { returns(String) }
    def get_cache_key
      "codespaces_usage_checker_#{billable_owner&.id}"
    end

    sig { returns(T.nilable(Symbol)) }
    def get_cached_allowed_reason
      cache_key = get_cache_key
      GitHub.context[cache_key]
    end

    sig { params(result: Codespaces::Access::AllowedResult).returns(NilClass) }
    def cache_allowed_reason(result)
      cache_key = get_cache_key
      GitHub.context.push({ cache_key => result.reason })
    end

    sig do
      params(
        sku_name: T.nilable(String),
        dev_container: T.nilable(Codespaces::DevContainer)
      ).returns(Codespaces::Access::AllowedResult)
    end
    def calculate_allowed_by_policy(sku_name:, dev_container:)
      GitHub.dogstats.increment("codespaces.usage_checker.policy_check")

      if sku_name && !Codespaces::MachinePolicy.machine_type_allowed?(sku_name:, billable_owner:, repository:)
        return Codespaces::Access::AllowedResult.new(Codespaces::Access::AllowedResult::DISALLOW_MACHINE_POLICY)
      end

      if dev_container && !Codespaces::ImagePolicy.image_allowed?(image_name: dev_container.image, repository:, billable_owner:)
        return Codespaces::Access::AllowedResult.new(Codespaces::Access::AllowedResult::DISALLOW_IMAGE_POLICY)
      end

      Codespaces::Access::AllowedResult.allowed
    end

    sig { returns(T.nilable(T::Boolean)) }
    def billing_v_next_enabled?
      cache_key = "codespaces_access_checker_billing_v_next_enabled_#{billable_owner&.id}"
      vnext_enabled = GitHub.context[cache_key]
      return vnext_enabled unless vnext_enabled.nil?

      vnext_enabled = billable_owner&.billing_customer&.billing_platform_enabled_product&.codespaces?
      GitHub.context.push({ cache_key => !!vnext_enabled })

      vnext_enabled
    end

    sig { params(fast_timeout: T::Boolean, copilot_workspace: T::Boolean).returns(T.any(Codespaces::Access::CopilotWorkspaceBillingChecker, Codespaces::Access::MeuseBillingChecker, Codespaces::Access::VNextBillingChecker)) }
    def get_billing_access_checker(fast_timeout:, copilot_workspace: false)
      if copilot_workspace
        raise ArgumentError, "a user must be provided in order to check usage for Copilot Workspaces" unless user
        Codespaces::Access::CopilotWorkspaceBillingChecker.new(user)
      elsif billing_v_next_enabled?
        Codespaces::Access::VNextBillingChecker.new(billable_owner, user_id: user&.id, repository:, fast_timeout:)
      else
        Codespaces::Access::MeuseBillingChecker.new(billable_owner, fast_timeout:)
      end
    end
  end
end
