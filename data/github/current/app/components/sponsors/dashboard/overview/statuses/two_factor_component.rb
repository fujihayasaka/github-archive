# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::Statuses::TwoFactorComponent < ApplicationComponent
  extend T::Sig

  include Sponsors::Dashboard::Overview::Statuses::ViewComponentMethods

  sig do
    override.params(
      sponsors_listing: SponsorsListing,
      adminable: T::Boolean,
      two_factor_auth_enabled: T::Boolean
    ).void
  end
  def initialize(sponsors_listing:, adminable: false, two_factor_auth_enabled: false)
    @sponsors_listing = sponsors_listing
    @adminable = adminable
    @two_factor_auth_enabled = two_factor_auth_enabled
  end

  sig { override.returns(T::Boolean) }
  def render?
    !sponsors_listing.disabled?
  end

  sig { override.returns(T::Boolean) }
  memoize def step_complete?
    two_factor_set?
  end

  private

  sig { returns(T::Boolean) }
  memoize def two_factor_set?
    if sponsorable.organization?
      @adminable && @two_factor_auth_enabled
    else
      sponsorable.two_factor_authentication_enabled?
    end
  end

  sig { returns(T::Boolean) }
  memoize def two_factor_recommended?
    this_sponsorable = sponsorable
    return false unless this_sponsorable.is_a?(Organization)
    !this_sponsorable.two_factor_requirement_enabled?
  end

  sig { returns(String) }
  def two_factor_status_icon
    two_factor_set? ? "check" : "dot-fill"
  end

  sig { returns(Symbol) }
  def two_factor_status_color
    two_factor_set? ? :success : :attention
  end
end
