# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::Statuses::ProfileComponent < ApplicationComponent
  extend T::Sig

  include Sponsors::Dashboard::Overview::Statuses::ViewComponentMethods

  sig { override.returns(T::Boolean) }
  def render?
    !sponsors_listing.disabled?
  end

  sig { override.returns(T::Boolean) }
  memoize def step_complete?
    bio_set?
  end

  private

  delegate :sponsorable_login, to: :sponsors_listing

  sig { returns(T::Boolean) }
  memoize def bio_set?
    sponsors_listing.full_description.present?
  end

  sig { returns(String) }
  def profile_status_icon
    bio_set? ? "check" : "dot-fill"
  end

  sig { returns(Symbol) }
  def profile_status_color
    bio_set? ? :success : :attention
  end
end
