# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TopicSuggestionDeclineReason < Platform::Enums::Base
      description "Reason that the suggested topic is declined."

      DeprecationNotice = {
        start_date: Date.new(2023, 12, 20),
        reason: "Suggested topics are no longer supported",
        superseded_by: nil,
        owner: "calvinchilds",
      }

      value "NOT_RELEVANT", "The suggested topic is not relevant to the repository.",
        value: :not_relevant, deprecated: DeprecationNotice
      value "TOO_SPECIFIC", "The suggested topic is too specific for the repository " +
                            "(e.g. #ruby-on-rails-version-4-2-1).", value: :too_specific, deprecated: DeprecationNotice
      value "PERSONAL_PREFERENCE", "The viewer does not like the suggested topic.",
        value: :personal_preference, deprecated: DeprecationNotice
      value "TOO_GENERAL", "The suggested topic is too general for the repository.",
        value: :too_general, deprecated: DeprecationNotice
    end
  end
end
