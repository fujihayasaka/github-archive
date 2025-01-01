# typed: false
# frozen_string_literal: true

module Stafftools::ReservedLoginsHelper
  def expiry_date_in_words(expires_at)
    if expires_at.nil?
      "expiring never"
    elsif expires_at.future?
      "expiring in #{distance_of_time_in_words Time.now, expires_at}"
    else
      "expired #{time_ago_in_words expires_at} ago"
    end
  end
end
