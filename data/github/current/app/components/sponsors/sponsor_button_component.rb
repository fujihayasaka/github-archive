# typed: true
# frozen_string_literal: true

class Sponsors::SponsorButtonComponent < ApplicationComponent
  include SponsorsButtonsHelper

  DEFAULT_LOCATION = :UNKNOWN
  DEFAULT_ICON_MARGIN_RIGHT = 1

  # sponsorable - a User, Organization, or their string login
  # is_sponsoring - optional Boolean; represents whether the viewer is currently sponsoring
  #                 the sponsorable user/org; if omitted, will be calculated
  # span_classes - optional String of CSS classes for the span tag surrounding the
  #                text in the link
  # icon_margin_right - optional number between 0-6 (see https://primer.style/css/utilities/margin)
  #                     or an array for responsive breakpoints
  #                     (see https://primer.style/view-components/system-arguments#responsive-values)
  #                     for the right margin on the icon, separating it from the text
  # location - optional Symbol describing where this button is being displayed, for use in
  #            Hydro click tracking; defaults to unknown
  # sponsor_login - String login for the User or Organization who should be selected as the sponsor
  # hide_text - optional Boolean describing whether or not to show 'Sponsor'/'Sponsoring' next
  #             to the heart icon; defaults to false such that text is shown
  def initialize(
    sponsorable:,
    is_sponsoring: nil,
    span_classes: nil,
    icon_margin_right: DEFAULT_ICON_MARGIN_RIGHT,
    location: nil,
    sponsor_login: nil,
    hide_text: false,
    **kwargs
  )
    @sponsorable = sponsorable
    @is_sponsoring = is_sponsoring
    @span_classes = span_classes || "v-align-middle"
    @hide_text = hide_text
    @icon_margin_right = @hide_text ? 0 : icon_margin_right
    @location = if location
      fetch_or_fallback(SPONSORS_BUTTON_LOCATIONS, location, DEFAULT_LOCATION)
    else
      DEFAULT_LOCATION
    end
    @sponsor_login = sponsor_login
    @kwargs = kwargs
  end

  private

  def render?
    @sponsorable.present? && !(@sponsorable.respond_to?(:sponsors_listing) && @sponsorable.sponsors_listing&.sdn_disabled?)
  end

  attr_reader :span_classes

  def hide_text?
    @hide_text
  end

  memoize def sponsoring?
    if @is_sponsoring.nil?
      if @sponsorable.respond_to?(:sponsored_by_viewer?)
        @sponsorable.sponsored_by_viewer?(current_user)
      else
        # If just a user login was given and is_sponsoring wasn't provided,
        # assume the viewer is not sponsoring this sponsorable
        false
      end
    else
      @is_sponsoring
    end
  end

  def link_component
    @kwargs[:tag] ||= :a
    @kwargs[:href] = sponsorable_path(@sponsorable, sponsor: @sponsor_login)
    @kwargs[:size] ||= :small
    @kwargs["aria-label"] ||= "#{button_text} @#{@sponsorable}"
    @kwargs[:data] ||= sponsors_button_hydro_attributes(@location, @sponsorable.to_s)
    @kwargs[:test_selector] = sponsoring? ? "sponsoring-button" : "sponsor-button"
    Primer::Beta::Button.new(**@kwargs)
  end

  def icon_component
    icon_classes = sponsoring? ? "icon-sponsoring" : "icon-sponsor"
    Primer::Beta::Octicon.new(
      icon: icon,
      mr: @icon_margin_right,
      vertical_align: :middle,
      classes: icon_classes,
      color: :sponsors,
      animation: animate_button? ? :pulse_in : nil,
    )
  end

  def icon
    sponsoring? ? "heart-fill" : "heart"
  end

  def animate_button?
    return false if sponsoring?
    return false if viewer_represents_sponsorable?

    true
  end

  def viewer_is_the_sponsorable?
    return false unless logged_in?
    return false unless @sponsorable.respond_to?(:user?)
    @sponsorable.user? && current_user == @sponsorable
  end

  def viewer_is_org_member?
    return false unless logged_in?
    return false unless @sponsorable.respond_to?(:organization?)
    @sponsorable.organization? && @sponsorable.direct_member?(current_user)
  end

  memoize def viewer_represents_sponsorable?
    viewer_is_the_sponsorable? || viewer_is_org_member?
  end

  memoize def button_text
    sponsoring? ? "Sponsoring" : "Sponsor"
  end
end
