# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class NotificationsSubject < Platform::Unions::Base
      description "The notification's subject."
      mobile_only true
      required_capabilities [:access_internal_graphql_notifications]

      possible_types(
        Objects::WorkflowRun,
        Objects::CheckSuite,
        Objects::Commit,
        Objects::Gist,
        Objects::TeamDiscussion,
        Objects::Issue,
        Objects::PullRequest,
        Objects::Release,
        Objects::RepositoryInvitation,
        Objects::RepositoryVulnerabilityAlert,
        Objects::RepositoryAdvisory,
        Objects::AdvisoryCredit,
        Objects::Discussion,
        Objects::SecurityAdvisory,
        Objects::RepositoryDependabotAlertsThread,
        Objects::MemberFeatureRequestNotification,
        Objects::ProjectV2
      )
    end
  end
end
