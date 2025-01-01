# typed: true
# frozen_string_literal: true

module Notifyd
  module NotificationBuilders
    module Syllabus
      REASONS_TO_WORDS = T.let({
        "mention" => "you were mentioned",
        "comment" => "you commented on the thread",
        "author" => "you authored the thread",
        "manual" => "you are subscribed to this thread",
        "team_mention" => "you are on a team that was mentioned",
        "assign" => "you were assigned",
        "review_requested" => "your review was requested",
        "state_change" => "you modified the open/close state",
        "security_alert" => "you have alerting access",
        "ci_activity" => "this workflow ran on your branch",
        "security_advisory_credit" => "you were given credit for contributing to a Security Advisory",
        "approval_requested" => "your approval was requested for deployment",
        "member_feature_requested" => "you have pending member feature requests",
      }, T::Hash[String, String])
    end
  end
end
