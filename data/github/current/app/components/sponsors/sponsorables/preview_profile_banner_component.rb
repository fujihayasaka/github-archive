# typed: true
# frozen_string_literal: true

class Sponsors::Sponsorables::PreviewProfileBannerComponent < ApplicationComponent

  # previewing - a Boolean representing whether the user is previewing the Sponsors profile
  # sponsors_listing - the SponsorsListing represented by the profile
  def initialize(previewing:, sponsors_listing:)
    @sponsors_listing = sponsors_listing
    @previewing = previewing
  end

  private

  attr_reader :sponsors_listing, :previewing

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    return false unless sponsors_listing.present?
    previewing || current_user&.login == sponsors_listing&.sponsorable_login
  end

  def preview_subject
    preview_subject = if current_user&.login == sponsors_listing.sponsorable_login
      "your"
    else
      "#{sponsors_listing.sponsorable_login}’s"
    end
    if !sponsors_listing.approved? && current_user&.can_admin_sponsors_listings?
      preview_subject += " #{sponsors_listing.current_state_name.to_s.humanize}"
    end
    preview_subject
  end

  def admin?
    sponsors_listing.adminable_by?(current_user)
  end

  def show_state_label?
    return false unless current_user&.can_admin_sponsors_listings?
    sponsors_listing.banned? || sponsors_listing.spammy?
  end
end
