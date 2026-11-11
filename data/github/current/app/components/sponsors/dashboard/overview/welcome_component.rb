# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::WelcomeComponent < ApplicationComponent
  include AvatarHelper

  SPONSORS_LIMIT = 6

  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  delegate :csrf_hidden_input_for, to: :view_context
  delegate :sponsorable_login, :for_organization?, :total_monthly_pledged_in_dollars, to: :sponsors_listing

  def render?
    sponsors_listing && !sponsors_listing.disabled? && logged_in?
  end

  def stripe_account?
    return false if sponsors_listing.blank?

    sponsors_listing.stripe_transfers_enabled?
  end

  def stripe_balance
    sponsors_listing.active_stripe_account_balance
  end

  def column_size_class
    stripe_account? ? "col-md-4" : "col-md-6"
  end

  memoize def sponsorships_scope
    sponsors_listing
      .active_sponsorships
      .with_linked_org_preloads
      .order(updated_at: :desc)
  end

  def sponsors_count
    sponsorships_scope.count
  end

  memoize def sponsorships
    sponsorships_scope.limit(SPONSORS_LIMIT).to_a
  end

  memoize def sponsors_logins
    sponsorships.map { |s| s.linked_or_direct_sponsor.display_login }.uniq.to_sentence
  end

  def dismiss_url
    dismiss_notice_path("first_sponsor")
  end

  def dismissed_first_sponsor?
    current_user.dismissed_notice?("first_sponsor")
  end

  def dismissed_welcome?
    current_user.dismissed_notice?("welcome_to_sponsors")
  end
end
