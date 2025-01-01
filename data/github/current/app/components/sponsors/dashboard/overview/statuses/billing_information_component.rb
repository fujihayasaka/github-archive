# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::Statuses::BillingInformationComponent < ApplicationComponent
  include Sponsors::Dashboard::Overview::Statuses::ViewComponentMethods

  sig { override.returns(T::Boolean) }
  def render?
    !sponsors_listing.disabled?
  end

  sig { override.returns(T::Boolean) }
  memoize def step_complete?
    billing_info_set? && !has_trade_screening_restriction?
  end

  private

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  delegate :sponsorable, to: :sponsors_listing

  sig { returns(T::Boolean) }
  memoize def billing_info_set?
    sponsorable.has_saved_billing_information?
  end

  sig { returns(T::Boolean) }
  memoize def has_trade_screening_restriction?
    sponsorable.has_trade_screening_restriction?
  end

  sig { returns(T::Boolean) }
  def disable_form_inputs?
    return false unless billing_info_set?

    !sponsorable.is_allowed_to_edit_trade_screening_information?
  end

  sig { returns(String) }
  def profile_status_icon
    return "alert" if has_trade_screening_restriction?

    billing_info_set? ? "check" : "dot-fill"
  end

  sig { returns(Symbol) }
  def profile_status_color
    return :danger if has_trade_screening_restriction?

    billing_info_set? ? :success : :attention
  end

  # Should the view show the new linking billing information component
  sig { returns(T::Boolean) }
  def show_linking_billing_information?
    sponsorable.org_is_on_standard_tos?
  end
end
