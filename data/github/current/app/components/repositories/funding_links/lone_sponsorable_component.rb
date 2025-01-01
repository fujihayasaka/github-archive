# typed: true
# frozen_string_literal: true

class Repositories::FundingLinks::LoneSponsorableComponent < ApplicationComponent
  def initialize(sponsorable:, previewing: false)
    @sponsorable = sponsorable
    @previewing = previewing
  end

  private

  attr_reader :sponsorable

  def render?
    GitHub.sponsors_enabled? && sponsorable.present?
  end

  def previewing?
    @previewing
  end

  def viewer_is_sponsoring?
    sponsorable.sponsored_by_viewer?(current_user)
  end

  def show_sponsor_button_for_non_sponsor?
    return true if sponsorable.user? && sponsorable == current_user
    return true if sponsorable.organization? && sponsorable.adminable_by?(current_user)
    sponsorable.sponsorable_by?(current_user)
  end
end
