# typed: true
# frozen_string_literal: true

class Sponsors::Explore::TotalFundedComponent < ApplicationComponent
  # user - User or Organization whose sponsorships should be checked
  def initialize(user:)
    @user = user
  end

  private

  attr_reader :user

  delegate :organization?, to: :user

  def render?
    GitHub.sponsors_enabled? && user && logged_in? && (can_see_start_date? || can_see_total_funded?)
  end

  def total_funded
    user.total_funded_via_github_sponsors
  end

  memoize def can_see_total_funded?
    user.sponsorship_amounts_as_sponsor_readable_by?(current_user)
  end

  memoize def can_see_start_date?
    can_see_total_funded? || user.private_sponsor_identity_visible_to?(current_user)
  end

  memoize def start_date
    date = user.earliest_sponsorship_date_as_sponsor
    date&.strftime("%B %Y")
  end
end
