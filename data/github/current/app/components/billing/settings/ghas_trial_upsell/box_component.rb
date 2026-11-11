# typed: strict
# frozen_string_literal: true

class Billing::Settings::GhasTrialUpsell::BoxComponent < ApplicationComponent
  include AdvancedSecurityEntrypointHelper
  include ApplicationComponent::Rescuable

  rescue_from StandardError, with: :nothing

  LEARN_MORE_URL = "https://resources.github.com/security/tools/ghas-trial/"

  sig { returns(T.nilable(::Organization)) }
  attr_reader :organization

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { params(organization: T.nilable(::Organization), user: T.nilable(User), system_arguments: Primer::SystemArgumentsValue).void }
  def initialize(organization:, user:, **system_arguments)
    @organization = organization
    @user = user
    @system_arguments = system_arguments
  end

  sig { returns(String) }
  def ghas_trial_signup_path
    ghas_trial_requests_path(T.must(organization).display_login, utm_source: "product", utm_campaign: "growth", utm_content: organization&.plan_name)
  end

  sig { returns(T::Boolean) }
  def ghas_trial_enabled?
    ghas_trial.enabled?
  end

  sig { returns(T::Boolean) }
  def ghas_trial_expired?
    # ghas_trial.expired? returns nil when trial is not active
    !ghas_purchased_for_org? && has_active_or_expired_sales_serve_trial?
  end

  sig { returns(T::Boolean) }
  def show_request_button?
    !ghas_trial_enabled? && !ghas_trial_expired?
  end

  sig { returns(T::Boolean) }
  def show_enabled_status?
    ghas_trial_enabled? && !ghas_trial_expired?
  end

  sig { returns(T::Boolean) }
  def show_self_serve_cta?
    display_mode == :self_serve
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless organization.present?
    # We display sales-serve states, or any related upsells for sales-serve or self-serve
    return false unless show_sales_serve_state? || display_mode != :do_not_show
    GlobalInstrumenter.instrument("analytics.event",
      category: "ghas_trial_eligibility",
      action: "settings_billing_add_on_viewed",
      label: T.must(organization).id.to_s,
    )
    true
  end

  sig { returns(T::Boolean) }
  def show_sales_serve_state?
    # When a trial is active, advanced security is marked as purchased.
    # This is why we check for an active trial first, before checking purchase state.
    # We only want to display this component when:
    #  - They are eligible for a trial
    #  - They have an active trial
    #  - The trial has expired, but they have not purchased.
    return true if ghas_trial_enabled?
    return false if ghas_purchased_for_org?
    has_active_or_expired_sales_serve_trial?
  end

  private

  sig { returns(T::Boolean) }
  memoize def ghas_purchased_for_org?
    T.must(organization).advanced_security_purchased_for_entity?
  end

  sig { returns(T::Boolean) }
  memoize def has_active_or_expired_sales_serve_trial?
    T.must(organization).get_advanced_security_trial_expires_at.present?
  end

  sig { returns(EnterpriseCloudOnboard::GhasTrial) }
  memoize def ghas_trial
    EnterpriseCloudOnboard::GhasTrial.new(actor: current_user, billable_entity: @organization)
  end

  sig { returns(Symbol) }
  memoize def display_mode
    show_advanced_security_entrypoint?(organization: organization, user: user)
  end
end
