# frozen_string_literal: true

# Enables auto merge on a pull request
class GetPullRequestId
  class GraphQLQueryError < StandardError; end

  class GitHubValidationError < StandardError; end

  class MissingSubjectError < StandardError; end

  GetPullRequestIdQuery = GitHubGraphQL.client.parse <<-'GRAPHQL'
    query($ownerName: String!, $repoName: String!, $pullRequestNumber: Int!) {
      repository(name: $repoName, owner: $ownerName) {
        pullRequest(number: $pullRequestNumber) {
          id
        }
      }
    }
  GRAPHQL

  attr_reader :pull_request

  def initialize(pull_request:)
    @pull_request = pull_request
  end

  def run
    response = make_graphql_request(pull_request).to_h

    if (data = response.dig("data", "repository", "pullRequest"))
      errors = data["errors"]
      handle_model_errors(errors) unless errors.nil?
      data["id"]
    else
      handle_unprocessable(response)
    end
  end

  private

  # rubocop:disable Metrics/MethodLength
  def handle_unprocessable(response)
    errors = response["errors"]

    # We've received an unexpected error structure from GitHub
    if errors.count > 1
      increment_error(error_type: :unexpected_error_count)
      raise errors.join(", ")
    end

    error = errors.first
    error_message = error["message"]

    # We've received errors with no data
    if response["data"].nil?
      increment_error(error_type: :query_error)

      case error_message
      when /401 Unauthorized/
        raise GitHubGraphQL::UnauthorizedError, error_message
      when /\A5\d{2}/
        raise GitHubGraphQL::ServerError, error_message
      else
        raise GraphQLQueryError, error_message
      end
    end

    # We've received nil data with errors
    case error_message
    when /Could not resolve to a node with the global id of '.*'/
      increment_error(error_type: :pull_request_missing)
      raise MissingSubjectError, error_message
    else
      raise error
    end
  end
  # rubocop:enable Metrics/MethodLength

  def handle_model_errors(errors)
    message = errors.map do |error|
      "#{error['attribute']} #{error['shortMessage']}"
    end.join(", ")
    increment_error(error_type: :github_model_error)
    raise GitHubValidationError, message
  end

  def make_graphql_request(pull_request)
    start = Time.now.in_time_zone
    response = GitHubGraphQL.client.query(
      GetPullRequestIdQuery,
      context: {
        account: pull_request.repo.account,
      },
      variables: {
        ownerName: pull_request.repo.account.github_login,
        repoName: pull_request.repo.name,
        pullRequestNumber: pull_request.github_number,
      }
    )
    duration = Time.now.in_time_zone - start

    MetricsClient.timing("get_pull_request_id.graphql_request", duration)

    response
  end

  def increment_error(error_type:)
    MetricsClient.increment(
      "get_pull_request_id.error",
      tags: { error_type: error_type }
    )
  end
end
