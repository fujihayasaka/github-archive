# typed: true
# frozen_string_literal: true

require "github-proto-support"

class Api::Internal::Twirp < ::Api::Internal
  module Support
    module V1
      # Provides access to Support-relevant data.
      class AbuseReportsApiHandler < Api::Internal::Twirp::Handler
        handles_service(GitHub::Proto::Support::V1::AbuseReportsAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        connected_to_writing_for :create_abuse_report
        # Public: Implementation of the CreateAbuseReport Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::Users::V1::CreateAbuseReportRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # GitHub::Proto::Users::V1::CreateAbuseReportResponse.
        def create_abuse_report(req, env)
          # Reporting user, (optional)
          reporting_user_id = id_argument(req.reporting_user_id, env[:user_id])
          reporting_user = User.find_by(id: reporting_user_id)

          # Reported user (this will get overwritten if there is reported_content and it belongs to a different user)
          reported_user_login = req.reported_user
          if reported_user_login.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "reported_user")
          end

          reported_user = User.find_by(login: req.reported_user)
          if reported_user.nil?
            return Twirp::Error.not_found("user does not exist", argument: "reported_user")
          end

          # Content, (optional)
          reported_content = if req.reported_content_url
            GitHub::Resources.find_by_url(req.reported_content_url, suppress_warning: true)
          else
            nil
          end

          # Reason
          reason = AbuseReport.reasons.include?(req.reason) ? req.reason : "unspecified"

          report = AbuseReport.new(
            reporting_user: reporting_user,
            reported_user: reported_user,
            reported_content: reported_content,
            reason: reason)

          if report.save
            if reporting_user
              if reported_content
                reporting_user.instrument(:report_content, user: reported_user, actor: reporting_user, content_url: reported_content.url, classifier: reason)
              else
                reporting_user.instrument(:report_abuse, reported_user: reported_user, classifier: reason)
              end
            end

            {
              is_created: true
            }
          else
            {
              is_created: false
            }
          end
        end
      end
    end
  end
end
