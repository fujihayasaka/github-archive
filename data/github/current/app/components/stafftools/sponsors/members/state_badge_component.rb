# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::StateBadgeComponent < ApplicationComponent
  def initialize(state_octicon:, listing:, **system_arguments)
    @system_arguments = system_arguments
    @system_arguments[:tag] = :span
    @system_arguments[:test_selector] = "sponsors-listing-#{listing&.id}"
    @state_octicon = state_octicon
    @listing = listing
  end

  private

  attr_reader :system_arguments, :state_octicon, :listing

  def render?
    state_octicon.present? && listing.present?
  end

  def current_state
    listing.current_state_name.to_s.humanize
  end

  STATE_COLOR = {
    draft: :accent,
    approved: :success,
    disabled: :danger,
    spammy: :danger,
    banned: :danger,
  }.freeze

  def state_color
    STATE_COLOR.fetch(listing.current_state_name.to_sym, :attention)
  end
end
