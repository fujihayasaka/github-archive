# typed: true
# frozen_string_literal: true

module User::AccountTwoFactorRequirementDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { User }

  INTERRUPT_BYPASS_GRACE_PERIOD = 7.days

  included do
    T.bind(self, T.class_of(User))

    has_one :two_factor_requirement_metadata

    validates :two_factor_requirement_state, presence: true

    # Account-bases 2FA requirement states for the user. Does not include 2FA requirements derived from
    # Orgs/Enterprises to which the user belongs.
    # Possible states:
    # OPTIONAL   - No account-based 2FA requirement exists for the user.
    # REQUIRED   - Account-based 2FA is required for the user. UX interrupts cannot be bypassed.
    # WARNING    - User has been flagged for account-based 2FA requirement, but is still in the onboarding grace period.
    #              This user should have an associated row in the 'two_factor_requirement_metadata' table.
    # INTERRUPT  - User has been flagged for account-based 2FA requirement, but is still in the onboarding grace period.
    #              Users in this state experience more friction than the WARNING state and can bypass interrupts.
    # EXEMPT     - User has been manually exempted from account-based 2FA requirement, likely by GitHub support.
    TWO_FACTOR_REQUIREMENT_STATES = {
      optional: 0,
      required: 1,
      warning: 2,
      interrupt: 3,
      exempt: 4,
    }.freeze

    def self.account_two_factor_requirement_states
      TWO_FACTOR_REQUIREMENT_STATES
    end

    def account_two_factor_requirement_state
      TWO_FACTOR_REQUIREMENT_STATES.keys[two_factor_requirement_state_raw]
    end

    def two_factor_requirement_state_raw
      return 0 if two_factor_requirement_metadata.nil?
      T.must(two_factor_requirement_metadata).state
    end
  end

  def has_forthcoming_account_two_factor_requirement?
    account_two_factor_requirement_state.in?([:warning, :interrupt, :required])
  end

  def in_account_2fa_requirement_warning_state?
    account_two_factor_requirement_state == :warning
  end

  def in_account_2fa_requirement_interrupt_state?
    account_two_factor_requirement_state == :interrupt
  end

  # Public: Returns true if user has been identified as belonging to a 2FA-required cohort -
  # someone who is required to have 2FA.
  #
  # Returns a boolean
  def in_account_2fa_requirement_required_state?
    self.account_two_factor_requirement_state == :required
  end

  def account_2fa_requirement_banner_recently_dismissed?
    last_dismiss = two_factor_requirement_metadata&.last_web_banner_dismissed_at
    return false if last_dismiss.nil?
    last_dismiss.utc > 1.week.ago.utc
  end

  def last_account_2fa_requirement_banner_dismissed_at
    two_factor_requirement_metadata&.last_web_banner_dismissed_at
  end

  # Determines if enabling 2FA should be celebrated for the user and which text to show in certain views
  def is_coerced_2fa_enrollment?
    account_two_factor_requirement_state.in?([:interrupt, :required]) || is_flagged_for_two_factor_checkup?
  end

  # Determines if the user should be shown the 2FA interrupt page
  def account_2fa_requirement_interrupt_required?
    # don't show the interrupt in GHES or Proxima
    return false if GitHub.single_or_multi_tenant_enterprise?

    # checking this prior to checking for two_factor_authentication_enabled? is a performance optimization
    # because it's cheaper to check this field on the existing user record than to check the two_factor_credentials table
    return false unless account_two_factor_requirement_state.in?([:interrupt, :required])

    # don't show the interrupt if the user has already enabled 2FA
    return false if two_factor_authentication_enabled?

    # check if the user has a bypass key in KV, if so, don't show the interrupt
    return false if account_2fa_requirement_interrupt_bypassed?

    # this should never happen, because all users with
    # two_factor_requirement_state != :optional set should have a two_factor_requirement_metadata record
    # but we are checking it here just in case and statting it out if it happens
    if two_factor_requirement_metadata.nil?
      GitHub.dogstats.increment("account_2fa_requirement_interrupt.missing_metadata")
      return false
    end

    return false unless self.feature_enabled?(:bulwark_two_factor_required_feature)

    true
  end

  def can_bypass_account_2fa_requirement_interrupt?
    account_two_factor_requirement_state != :required
  end

  def update_2fa_requirement_banner_metadata
    metadata = T.must(two_factor_requirement_metadata)

    metadata.last_web_banner_dismissed_at = Time.current.utc
    metadata.web_banner_dismissed_count = metadata.web_banner_dismissed_count + 1
    metadata.save
  end

  def bypass_account_2fa_requirement_interrupt_key
    "bypass-account-2fa-requirement-interrupt:#{self.id}"
  end

  def account_2fa_requirement_interrupt_bypassed?
    return false unless can_bypass_account_2fa_requirement_interrupt?
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:account_2fa_requirement_dependency"])
    GitHub::Authentication::KV.store.get(bypass_account_2fa_requirement_interrupt_key).value { nil } == "true"
  end

  def set_bypass_account_2fa_requirement_interrupt!
    metadata = T.must(two_factor_requirement_metadata)

    begin
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:account_2fa_requirement_dependency"])
      GitHub::Authentication::KV.store.set(bypass_account_2fa_requirement_interrupt_key, "true", expires: Time.current.utc.end_of_day)
      bypass_count = metadata.interrupt_bypass_count
      metadata.update!(interrupt_bypass_count: bypass_count + 1) if bypass_count < 127
    rescue GitHub::KV::UnavailableError
      GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :two_factor_requirement_interrupt, action: :set })
    end
  end

  def instrument_update_two_factor_requirement_state(payload = {})
    instrument :update_two_factor_requirement_state, payload.merge(
      new_state: self.account_two_factor_requirement_state.to_s
    )
  end
end
