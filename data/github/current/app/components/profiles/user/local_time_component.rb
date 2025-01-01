# typed: true
# frozen_string_literal: true

# Renders the user's local time (as long as they opted-in and selected a
# timezone in their profile settings), followed by a <profile-timezone> tag that
# initially contains the user's local time zone described by its UTC drift, e.g.
# "(UTC +02:00)".
#
# As long as this isn't a user viewing their own profile/hovercard (that is, the
# user isn't the currently logged-in user), the tag will als contain a parameter
# that triggers app/components/profiles/profile-timezone-element.ts to rewrite
# the drift as "x hours ahead / behind" (relative to the viewer's browser/OS
# time zone)

class Profiles::User::LocalTimeComponent < ApplicationComponent
  def initialize(user:, classes: nil, timezone_classes: "d-inline", local_time: nil)
    @user = user
    @classes = classes
    @timezone_classes = timezone_classes
    @local_time = local_time

    if local_time.nil? && render?
      @local_time = Time.now.in_time_zone(user.profile_local_time_zone_name)
    end
  end

  attr_accessor :user, :classes, :timezone_classes

  def render?
    @user.profile.present? && @user.profile.local_time_zone_name.present?
  end

  def time_in_24h_format
    @local_time.strftime("%H:%M")
  end

  def timezone_as_utc_plus_minus_hours
    @local_time.strftime("(UTC %:z)").gsub(/ .00:00/, "")
  end

  def hours_ahead_of_utc
    @local_time.utc_offset.to_f / 1.hour
  end
end
