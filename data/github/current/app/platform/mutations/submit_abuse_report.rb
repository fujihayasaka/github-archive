# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SubmitAbuseReport < Platform::Mutations::Base
      description "Report content as abusive."
      minimum_accepted_scopes ["public_repo"]
      visibility :internal

      argument :reported_content, ID, "The content being reported.", required: true, loads: Interfaces::AbuseReportable
      argument :reason, Enums::AbuseReportReason, "The reason for the report.", required: true

      def self.async_api_can_modify?(permission, reported_content:, **inputs)
        repository = reported_content.repository
        permission.access_allowed?(:report_content,
          repo: repository,
          current_org: repository.organization,
          resource: reported_content,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )
      end

      def resolve(reported_content:, reason:)
        authorization = ContentAuthorizer.authorize(context[:viewer], :report_content, :create, reported_content: reported_content)
        if authorization.failed?
          raise Errors::Unprocessable.new("You cannot report this content.")
        end

        abuse_report = AbuseReport.create(
          reporting_user: context[:viewer],
          reported_user: reported_content.user,
          reported_content: reported_content,
          repository_id: reported_content.repository,
          reason: reason.downcase,
          show_to_maintainer: true,
        )

        if abuse_report.errors&.any?
          raise Errors::Unprocessable.new(abuse_report.errors.map(&:message).to_sentence)
        end

        {}
      end
    end
  end
end
