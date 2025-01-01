# typed: true
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class DetectedSecretRowComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      include DiffHelper

      def initialize(alert, alert_url)
        @type = alert.label
        @internal_type = alert.type
        @alert_url = GitHub.url + alert_url
        @alert_location_text = alert_location_text(alert)
      end

      def alert_location_text(alert)
        location = alert.first_location
        if location.nil?
          return ""
        end

        case location.content_type
        when :REPOSITORY_BLOB, :WIKI_BLOB
          "#{reverse_truncate(alert.first_location.path)}#L#{(alert.first_location.start_line)} • commit #{alert.first_location.commit_oid[0..7]}"
        when :ISSUE_TITLE, :ISSUE_BODY, :ISSUE_COMMENT
          "issue ##{location.content_number}"
        when :DISCUSSION_TITLE, :DISCUSSION_BODY, :DISCUSSION_COMMENT
          "discussion ##{location.content_number}"
        when :PULL_REQUEST_TITLE, :PULL_REQUEST_BODY, :PULL_REQUEST_COMMENT, :PULL_REQUEST_REVIEW, :PULL_REQUEST_TIMELINE_COMMENT, :PULL_REQUEST_REVIEW_COMMENT
          "pull request ##{location.content_number}"
        end
      end
    end
  end
end
