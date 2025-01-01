# typed: false
# frozen_string_literal: true

module Stafftools::NewsiesReasons
  HUMANIZATIONS = {
    "assign"       => "assigned",
    "comment"      => "commented",
    "list"         => "watching repository",
    "mention"      => "directly mentioned",
    "milestone"    => "subscribed to a mentioned milestone",
    "state_change" => "modified the open/close state",
    "team_mention" => "on a mentioned team",
    "review_requested" => "review requested",
  }

  def human_reason
    HUMANIZATIONS[reason] || reason
  end
end
