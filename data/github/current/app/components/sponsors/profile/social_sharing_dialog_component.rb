# typed: strict
# frozen_string_literal: true

class Sponsors::Profile::SocialSharingDialogComponent < ApplicationComponent
  sig do
    params(
      sponsorable: User,
      sponsor: User,
      sponsorship: T.nilable(Sponsorship)
    ).void
  end
  def initialize(sponsorable:, sponsor:, sponsorship: nil)
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsorship = sponsorship
  end

  private

  sig { returns String }
  def share_default_text
    "I just sponsored #{@sponsorable.display_login}. Go sponsor your open source dependencies!"
  end

  sig { returns T::Hash[String, String] }
  def share_button_data
    helpers.sponsors_button_hydro_attributes(
      :SPONSORS_PROFILE_SHARE,
      @sponsorable.display_login,
    )
  end

  sig { returns T::Hash[String, String] }
  def share_button_url_params
    Sponsors::TrackingParameters.new(
      origin: Sponsors::TrackingParameters::SPONSORS_PROFILE_ORIGIN,
      referring_account_login: @sponsor.display_login,
    ).to_h
  end

  sig { returns T::Hash[String, String] }
  def clipboard_button_data
    helpers.sponsors_button_hydro_attributes(:SOCIAL_SHARE_CLIPBOARD, @sponsorable.display_login).merge(
      copy_feedback: "Copied Sponsors profile link to clipboard!",
      tooltip_direction: "sw",
    )
  end

  sig { returns String }
  def sponsors_profile_url
    "https://github.com/sponsors/#{@sponsorable.display_login}?sp=#{@sponsor.display_login}"
  end

  sig { returns T::Boolean }
  def render?
    return false unless @sponsorship.present?
    T.let(logged_in?, T::Boolean) && @sponsorship.active?
  end
end
