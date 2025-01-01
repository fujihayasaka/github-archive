# typed: true
# frozen_string_literal: true

class Sponsors::Profile::SocialSharingComponent < ApplicationComponent
  include SponsorsButtonsHelper

  def initialize(sponsorable:, sponsor:, sponsorship: nil, autofocus: false)
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsorship = sponsorship
    @autofocus = autofocus
  end

  private

  def sponsors_profile_url
    "https://github.com/sponsors/#{@sponsorable.display_login}?sp=#{@sponsor.display_login}"
  end

  def default_text
    "#{Emoji.find_by_alias("sparkling_heart").raw} I'm sponsoring #{@sponsorable.display_login} because…"
  end

  def render?
    return false unless logged_in?
    return false unless @sponsorship&.active?

    GlobalInstrumenter.instrument("sponsors.element_displayed", {
      element: "SOCIAL_SHARING_CTA",
      actor: current_user,
      sponsor: @sponsor,
      sponsorable: @sponsorable,
    })

    true
  end
end
