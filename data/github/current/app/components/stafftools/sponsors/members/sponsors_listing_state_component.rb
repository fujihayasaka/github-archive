# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::SponsorsListingStateComponent < ApplicationComponent
  def initialize(listing:)
    @listing = listing
  end

  def call
    render(Stafftools::Sponsors::Members::StateBadgeComponent.new(**badge_args))
  end

  private

  attr_reader :listing

  def render?
    listing.present?
  end

  def datetime_label
    "#{current_state_label} since #{since.to_formatted_s(:long)}" if since.present?
  end

  def since
    @listing.in_current_state_since
  end

  def include_tooltip?
    since.present?
  end

  def current_state
    @listing.current_state_name
  end

  def current_state_label
    current_state.to_s.humanize
  end

  STATE_OCTICON = {
    draft: "pencil",
    approved: "check",
    disabled: "circle-slash",
    spammy: "alert",
  }.freeze

  def state_octicon
    STATE_OCTICON.fetch(current_state.to_sym, "eye")
  end

  def badge_args
    args = {
      state_octicon: state_octicon,
      listing: listing,
    }

    if include_tooltip?
      args = args.merge({
        classes: "no-wrap h6 tooltipped tooltipped-n",
        "aria-label": datetime_label,
      })
    end

    args
  end
end
