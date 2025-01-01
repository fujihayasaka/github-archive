# typed: true
# frozen_string_literal: true

class Mail::ThankSponsorsComponent < ApplicationComponent

  def initialize(sponsorable:, sponsor:, sponsorship: nil, sponsoring:, params: {})
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsorship = sponsorship
    @sponsoring = sponsoring
    @params = params
  end

  private

  def sponsors_profile_url
    URI::HTTPS.build(
      host: "github.com",
      path: "/sponsors/#{@sponsorable.display_login}",
      query: Sponsors::TrackingParameters.new(**{
          source: Sponsors::TrackingParameters::TWITTER_SOURCE
        }.merge(@params)
      ).to_h.to_query)
  end

  def default_text_sponsor
    name_for_share = "@#{@sponsor.display_login}"

    "Thank you #{name_for_share} for sponsoring me on @github. You can join them at my sponsors profile: #{sponsors_profile_url}"
  end

  def default_text_sponsoring
    name_for_share = "@#{@sponsorable.display_login}"

    "I just sponsored #{name_for_share}. Go Sponsor your open source dependencies! You can join me at: #{sponsors_profile_url}"
  end
end
