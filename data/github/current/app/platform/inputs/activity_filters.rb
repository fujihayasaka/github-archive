# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class ActivityFilters < Platform::Inputs::Base
      description "Ways in which to filter lists of activities."

      argument :ref,
        String,
        "The Git reference for the activities you want to list. The `ref` for a branch can be formatted either as `refs/heads/BRANCH_NAME` or `BRANCH_NAME`, where `BRANCH_NAME` is the name of your branch.",
        required: false

      argument :actor,
        String,
        "The GitHub username to use to filter by the actor who performed the activity.",
        required: false

      argument :time_period,
        Enums::ActivityPeriod,
        "The time period to filter by. For example, `day` will filter for activity that occurred in the past 24 hours, and `week` will filter for activity that occurred in the past 7 days (168 hours).",
        required: false

      argument :activity_type,
        Enums::ActivityType,
        "The activity type to filter by. For example, you can choose to filter by \"force_push\", to see all force pushes to the repository.",
        required: false
    end
  end
end
