# typed: true
# frozen_string_literal: true

require "monolith-twirp-support-helphub"

module Api::Internal::Twirp::Support
  module HelpHub
    module V1
      # Provides access to Support-relevant data.
      class AbuseReportsApiHandler < Api::Internal::Twirp::Handler
        handles_service(MonolithTwirp::Support::HelpHub::V1::AbuseReportsAPIService)

        allow_access_for :user, :client, allowed_clients: %w(helphub).freeze

        connected_to_writing_for :create_abuse_report
        # Public: Implementation of the CreateAbuseReport Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::CreateAbuseReportRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::CreateAbuseReportResponse.
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
            GitHub::Resources.find_by_url(
              req.reported_content_url, suppress_warning: true)
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
                reporting_user.instrument(:report_content, user: reported_user, actor: reporting_user, content_url: req.reported_content_url, classifier: reason)
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

        # Public: Implementation of the GetReportedContent Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::GetReportedContentRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::GetReportedContentResponse.
        def get_reported_content(req, env)
          content_object = GitHub::Resources.find_by_url(
            req.reported_content_url, suppress_warning: true)

          if content_object.nil?
            return Twirp::Error.not_found("Content not found", argument: "reported_content_url")
          end

          # Only public content is reportable. See AbuseReportable#async_viewer_can_report?
          unless content_object.is_a?(Gist) || content_object.is_a?(GistComment) || content_object.try(:repository)&.public?
            return Twirp::Error.not_found("Reportable content not found", argument: "reported_content_url")
          end

          {
            reported_content_id: content_object.id,
            reported_content_type: content_object.class.name.underscore.upcase,
            reported_content: [content_object.try(:title), content_object.try(:body)].compact.join("\n").truncate(32_000)
          }.compact
        end

        # Public: Implementation of the GetReportedIntegration Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Support::HelpHub::V1::GetReportedIntegrationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data as a Hash suitable for use in a
        # MonolithTwirp::Support::HelpHub::V1::GetReportedIntegrationResponse.
        def get_reported_integration(req, env)
          app = Integration.find_by(id: req.id)
          if app.nil?
            return Twirp::Error.not_found("Integration not found", argument: "id")
          end

          domain = begin
            URI(app.url).hostname
          rescue ArgumentError, URI::InvalidURIError
            nil
          end

          {
            id: app.id,
            name: app.name,
            domain: domain,
            url: app.url,
            callback_url: app.callback_url,
            is_public: app.public?,
            created_at: Google::Protobuf::Timestamp.new(seconds: app.created_at.to_i),
            owner_id: app.owner_id,
            bot_id: app.bot_id
          }.compact
        end
      end
    end
  end
end
