# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::StatusComponent < ApplicationComponent
  extend T::Sig

  sig { params(sponsors_listing: SponsorsListing).void }
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  delegate :sponsorable_login, :current_state_name, :sponsorable, to: :sponsors_listing

  sig { returns(T::Array[ApplicationComponent]) }
  memoize def all_required_steps
    required_steps = T.let([
      status_profile_component,
      status_billing_information_component,
      status_two_factor_component,
      status_stripe_connect_component,
      status_publish_component
    ], T::Array[ApplicationComponent])
  end

  sig { returns(T::Array[ApplicationComponent]) }
  memoize def incomplete_required_steps
    all_required_steps.select { |s| s.render? && !s.try(:step_complete?) }
  end

  sig { returns(T::Array[ApplicationComponent]) }
  memoize def completed_steps
    all_required_steps.select do |s|
      s.render? && s.try(:step_complete?)
    end
  end

  sig { returns(T::Boolean) }
  def show_incomplete_required_steps?
    incomplete_required_steps.any? && !sponsors_listing.disabled?
  end

  sig { returns(T::Boolean) }
  memoize def show_completed_steps?
    completed_steps.any?
  end

  sig { returns(Sponsors::Dashboard::Overview::Statuses::ProfileComponent) }
  def status_profile_component
    Sponsors::Dashboard::Overview::Statuses::ProfileComponent.new(sponsors_listing: sponsors_listing)
  end

  sig { returns(Sponsors::Dashboard::Overview::Statuses::TwoFactorComponent) }
  def status_two_factor_component
    Sponsors::Dashboard::Overview::Statuses::TwoFactorComponent.new(
      sponsors_listing: sponsors_listing,
      adminable: sponsorable.adminable_by?(current_user),
      two_factor_auth_enabled: current_user.two_factor_authentication_enabled?,
    )
  end

  sig { returns(Sponsors::Dashboard::Overview::Statuses::StripeConnectComponent) }
  def status_stripe_connect_component
    Sponsors::Dashboard::Overview::Statuses::StripeConnectComponent.new(sponsors_listing: sponsors_listing)
  end

  sig { returns(Sponsors::Dashboard::Overview::Statuses::BillingInformationComponent) }
  def status_billing_information_component
    Sponsors::Dashboard::Overview::Statuses::BillingInformationComponent.new(sponsors_listing: sponsors_listing)
  end

  sig { returns(Sponsors::Dashboard::Overview::Statuses::PublishComponent) }
  def status_publish_component
    Sponsors::Dashboard::Overview::Statuses::PublishComponent.new(sponsors_listing: sponsors_listing)
  end

  sig { returns(T.nilable(String)) }
  memoize def incomplete_required_steps_header_text
    return if sponsors_listing.approved?

    if sponsors_listing.pending_approval?
      "Your profile is pending approval, and isn't live yet."
    elsif sponsors_listing.ready_for_submission?
      "Your profile isn't live yet. Click the publish button to continue."
    else
      "Your profile isn't live yet. We need more information to continue."
    end
  end

  sig { returns(String) }
  def completed_steps_header_text
    if sponsors_listing.approved?
      "All requirements have been met"
    else
      "Completed steps"
    end
  end
end
