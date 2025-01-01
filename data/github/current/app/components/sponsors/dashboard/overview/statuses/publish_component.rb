# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::Statuses::PublishComponent < ApplicationComponent
  extend T::Sig

  include Sponsors::Dashboard::Overview::Statuses::ViewComponentMethods

  sig { override.returns(T::Boolean) }
  def render?
    !sponsors_listing.disabled?
  end

  sig { override.returns(T::Boolean) }
  memoize def step_complete?
    approved?
  end

  private

  delegate :waiting_to_be_reviewed?, :approved?, :sponsorable_login, to: :sponsors_listing

  sig { returns(String) }
  def publish_status_icon
    if sponsors_listing.approved?
      "check"
    elsif sponsors_listing.waiting_to_be_reviewed?
      "clock"
    else
      "dot-fill"
    end
  end

  sig { returns T::Boolean }
  def show_publish_button?
    sponsors_listing.draft?
  end

  sig { returns(Symbol) }
  def publish_status_color
    approved? ? :success : :attention
  end

  sig { returns(T::Boolean) }
  def can_publish_listing?
    !!(sponsors_listing.ready_for_submission? && current_user.two_factor_authentication_enabled?)
  end
end
