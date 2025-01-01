# typed: true
# frozen_string_literal: true

module SecretScanning
  module AlertCentricView
    class TableRowComponent < ApplicationComponent
      include ScanningHelper
      include GitHub::TokenScanning::SecretScanningHelper
      include SecretScanning::Features::FeatureFlagHelper

      QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery

      FILE_PATH_TRUNCATION_LENGTH = 24

      attr_reader :alert, :show_alert_number

      def initialize(
        alert:,
        show_owner:,
        show_repository:,
        show_alert_number: true,
        show_unlock_dialog: false,
        query: nil
      )
        @alert = alert
        @show_owner = show_owner
        @show_repository = show_repository
        @show_alert_number = show_alert_number
        @show_unlock_dialog = show_unlock_dialog
        @query = query
        @repository_token_scanning_view_model = RepositoryTokenScanning::View.new
      end

      def first_detected_location
        case alert.first_location.content_type
        when :REPOSITORY_BLOB, :WIKI_BLOB
          location = truncated_file_path
          location += ":#{alert.first_location.start_line}" unless alert.found_in_archive?
          location
        when :ISSUE_TITLE, :ISSUE_BODY, :ISSUE_COMMENT
          issue = get_issue(alert.first_location.content_id)
          if issue.present? && issue.pull_request_id.present?
            "pull request ##{alert.first_location.content_number}"
          else
            "issue ##{alert.first_location.content_number}"
          end
        when :DISCUSSION_TITLE, :DISCUSSION_BODY, :DISCUSSION_COMMENT
          "discussion ##{alert.first_location.content_number}"
        when :PULL_REQUEST_TITLE, :PULL_REQUEST_BODY, :PULL_REQUEST_COMMENT, :PULL_REQUEST_REVIEW, :PULL_REQUEST_REVIEW_COMMENT, :PULL_REQUEST_TIMELINE_COMMENT
          "pull request ##{alert.first_location.content_number}"
        end

      end

      def label_href
        repository_react_alerts_show_path(alert.repository.owner, alert.repository, alert.number)
      end

      def raw_secret_display
        secret = SecretScanning::Util::RawSecret.token_literal_from_secret(alert.raw_secret)
        return SecretScanning::Util::RawSecret::NO_PREVIEW_MESSAGE if secret.nil?
        secret
      end

      memoize def resolution_description
        @repository_token_scanning_view_model.resolution_description(alert.resolution)
      end

      def secret_classification
        alert.is_custom? ? "custom pattern" : "secret"
      end

      def truncated_file_path
        reverse_truncate_path(
          alert.first_location.path,
          FILE_PATH_TRUNCATION_LENGTH
        )
      end

      def resolution_href
        slug_value = get_slug_value_from_alert_resolution(alert.resolution)
        new_query = QUERY_PARSER.toggle_qualifier(@query, QUERY_PARSER::QUALIFIER_RESOLUTION, slug_value)
        QUERY_PARSER.query_string_for_url(new_query)
      end

      def alert_closed?
        alert.resolved?
      end

      def alert_state_icon
        return "shield-check" if alert_closed?
        "shield"
      end

      def alert_state_label
        return "Closed as #{resolution_description}" if alert_closed?
        "Open alert"
      end

      def alert_state_changed_at
        alert_closed? ? alert.resolved_at : alert.created_at
      end

      def alert_number
        alert.number
      end

      sig { returns(T::Boolean) }
      def token_active?
        alert.validity_active?
      end

      # For repositories belonging to enterprise managed users, the current_user may not have access to the repository.
      def show_unlock_dialog?
        @show_unlock_dialog
      end

      private

      def get_issue(id)
        ActiveRecord::Base.connected_to(role: :reading) do
          alert.repository.issues.find_by(id: id)
        end
      end
    end
  end
end
