# typed: true
# frozen_string_literal: true

class Sponsors::PaypalDeprecationNoticeComponent < ApplicationComponent
  SIGNATURE_VIEW_CONTEXTS = Billing::Zuora::HostedPaymentsPage::SIGNATURE_VIEW_CONTEXTS

  # user_or_org - the User or Organization who might be a sponsor that uses PayPal
  # has_active_sponsorships - optional Boolean indicating whether the given user/org is a sponsor in any active
  #                           sponsorships, if known; if omitted, this will be calculated as necessary
  # signature_view_context - optional String
  # in_paypal_context - Boolean indicating whether this is being rendered on a form to select PayPal as the payment
  #                     method
  # include_link - Boolean indicating whether or not to link to the payment method page
  # system_arguments - Hash of keyword arguments. Applied to the outermost <div> as Primer system arguments. See
  #                    https://primer.style/view-components/system-arguments.
  def initialize(user_or_org:, has_active_sponsorships: nil, signature_view_context: nil, in_paypal_context: false, include_link: false, **system_arguments)
    @user_or_org = user_or_org
    @has_active_sponsorships = has_active_sponsorships
    @signature_view_context = if signature_view_context
      fetch_or_fallback(SIGNATURE_VIEW_CONTEXTS, signature_view_context, nil)
    end
    @in_paypal_context = in_paypal_context
    @include_link = include_link
    @system_arguments = system_arguments
  end

  private

  attr_reader :user_or_org, :system_arguments, :signature_view_context

  delegate :user_metadata, to: :user_or_org

  def render?
    return false unless GitHub.sponsors_enabled? && user_or_org.present? && logged_in?
    return false unless user_or_org.user? || user_or_org.organization? # not applicable to Business

    # If you're not looking at some Sponsors form or view and you aren't currently a sponsor, this notice
    # isn't relevant to you:
    return false unless in_sponsorship_context? || has_active_sponsorships?

    # An active sponsor looking at the PayPal form on the billing settings page should see the notice
    # regardless of whether they are currently using PayPal or not:
    return true if in_paypal_context? && on_billing_settings_page?

    # Are we rendering this notice from within the PayPal form such that the user could switch to using PayPal,
    # or are they already using PayPal? Either way, they should see the notice:
    in_paypal_context? || uses_paypal_for_sponsors?
  end

  memoize def in_sponsorship_context?
    signature_view_context == Billing::Zuora::HostedPaymentsPage::SPONSORS_SIGNATURE_VIEW_CONTEXT
  end

  def on_billing_settings_page?
    signature_view_context == Billing::Zuora::HostedPaymentsPage::BILLING_SETTINGS_SIGNATURE_VIEW_CONTEXT
  end

  def in_paypal_context?
    @in_paypal_context
  end

  memoize def uses_paypal_for_sponsors?
    user_or_org.has_paypal_account_for_sponsors?
  end

  def has_active_sponsorships?
    if @has_active_sponsorships.nil? # we don't already know, so need to check the database to see
      sponsorship_count.nonzero?
    else
      @has_active_sponsorships
    end
  end

  memoize def show_call_to_action?
    return true unless in_paypal_context?
    uses_paypal_for_sponsors? && has_active_sponsorships?
  end

  def description
    action = in_sponsorship_context? ? "pay by credit or debit card." : "continue sponsoring."
    "to #{action}"
  end

  def sponsorship_count
    user_metadata ? user_metadata.sponsoring_public_and_private_count : 0
  end

  def include_link?
    @include_link
  end

  def whose_payment_method
    user_or_org.user? ? "your" : "#{user_or_org}'s"
  end

  def update_payment_method_path
    return settings_org_billing_tab_path(user_or_org, tab: "payment_information") if user_or_org.organization?
    settings_user_billing_tab_path(tab: "payment_information")
  end

  def consequences_warning
    who_with_verb = user_or_org.user? ? "you are" : "#{user_or_org} is"
    "We will cancel your sponsorships if #{who_with_verb} #{"still" if uses_paypal_for_sponsors?} using PayPal then."
  end

  def payment_method_link_or_text
    if include_link?
      link_to("Update #{whose_payment_method} payment method", update_payment_method_path)
    else
      "Update #{whose_payment_method} payment method"
    end
  end
end
