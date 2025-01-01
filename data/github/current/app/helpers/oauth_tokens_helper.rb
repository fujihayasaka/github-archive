# typed: true
# frozen_string_literal: true

module OauthTokensHelper
  NO_EXPIRATION_NOTE = "The token will never expire!"

  def format_expiry_note(days)
    "The token will expire on #{days.days.from_now.strftime("%a, %b %e %Y")}"
  end

  def display_expiration_date(token)
    human_expiration_date(token.expires_at)
  end

  def human_expiration_date(expiration_time)
    return "" if expiration_time.nil?

    local_expiration_time = expiration_time.in_time_zone(Time.zone)
    if local_expiration_time.today?
      "today"
    elsif local_expiration_time.yesterday?
      "yesterday"
    else
      "on #{local_expiration_time.strftime("%a, %b %e %Y")}"
    end
  end

  def custom_expiration_timeframe?(timeframe)
    return false unless timeframe.present?

    %w[7 30 60 90].exclude?(timeframe.to_s)
  end

  def expiration_timeframes(allow_none: true)
    time_frames = [
      ["7 days", "7", { "data-human-date" => format_expiry_note(7) }],
      ["30 days", "30", { "data-human-date" => format_expiry_note(30) }],
      ["60 days", "60", { "data-human-date" => format_expiry_note(60) }],
      ["90 days", "90", { "data-human-date" => format_expiry_note(90) }],
      ["Custom...", "custom"],
    ]

    return time_frames unless allow_none

    time_frames << ["No expiration", "none", { "data-human-date" => NO_EXPIRATION_NOTE }]
  end

  def expiration_helper_note(access_token)
    if access_token.default_expires_at == "custom"
      ""
    elsif access_token.default_expires_at == "none"
      NO_EXPIRATION_NOTE
    else
      format_expiry_note(access_token.default_expires_at.to_i)
    end
  end
end
