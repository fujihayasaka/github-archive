# typed: false
# frozen_string_literal: true

module Api::Serializer::DeploymentRequestsDependency

  DeploymentRequestsFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on DeploymentRequest {
          environment {
            ...Api::Serializer::EnvironmentsDependency::EnvironmentFragment
          }
          currentUserCanApprove
          waitTimer
          waitTimerStartedAt
          reviewers(first: 100) {
            nodes {
              ... on User {
                ...Api::Serializer::UserDependency::SimpleUserFragment
              }
              ... on Team {
                ...Api::Serializer::OrganizationsDependency::SimpleTeamFragment
              }
            }
          }
    }
  GRAPHQL

  def graphql_deployment_request_hash(deployment_request, options)
    deployment_request = DeploymentRequestsFragment.new(deployment_request)
    return nil unless deployment_request

    {
      environment: graphql_simple_environment_hash(deployment_request.environment, options),
      wait_timer: deployment_request.wait_timer,
      wait_timer_started_at: deployment_request.wait_timer_started_at,
      current_user_can_approve: deployment_request.current_user_can_approve,
      reviewers: graphql_simple_deployment_reviewer_hash(deployment_request.reviewers.nodes, options)
    }
  end

  def graphql_simple_deployment_reviewer_hash(reviewers, options)
    return nil unless reviewers

    reviewers.map do |r|
      {
        type: r.__typename,
        reviewer: r.__typename == "User" ? graphql_simple_user_hash(r, options) : graphql_team_hash(r, options),
      }
    end
  end
end
