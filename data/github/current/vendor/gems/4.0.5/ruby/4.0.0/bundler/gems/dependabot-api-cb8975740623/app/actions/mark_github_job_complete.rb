# frozen_string_literal: true

# Marks the originating RepositoryDependencyUpdate object in GitHub as complete
# and associates it with a PullRequest
class MarkGitHubJobComplete
  class GitHubValidationError < StandardError; end

  class GitHubAppError < StandardError; end

  class MissingSubjectError < StandardError; end

  class StateError < StandardError; end

  class GraphQLQueryError < StandardError; end

  MarkAsCompleteQuery = GitHubGraphQL.client.parse <<-'GRAPHQL'
    mutation($databaseId: Int!, $pullRequestNumber: Int!) {
      markRepositoryDependencyUpdateComplete(input: { databaseId: $databaseId, pullRequestNumber: $pullRequestNumber }) {
        errors {
          attribute
          shortMessage
        }
      }
    }
  GRAPHQL

  attr_reader :update_job, :repo, :pull_request

  def initialize(update_job:, pull_request:)
    @update_job = update_job
    @repo = update_job.update_config.repo
    @pull_request = pull_request
  end

  def run
    return false if update_job.dry_run?
    return false unless job_actionable?

    response = make_graphql_request

    if (data = response.data&.mark_repository_dependency_update_complete)
      errors = data.errors
      handle_model_errors(errors) if errors.any?
      update_job.increment_metric("mark_github_job_complete.success")
      true
    else
      handle_unprocessable(response)
    end
  rescue GraphQL::Client::InvariantError
    # There appears to be a bug in the graphql-client schema validation
    # that means errors in the query `data` are not parsed correctly.
    #
    # This is likely due to it being a new-ish pattern used for internal
    # queries. Let's rescue it knowing it means RepositoryDependencyUpdate
    # has unexpected validation errors.
    increment_error(error_type: :github_model_error)
    raise GitHubValidationError, "#{update_job.github_request_id} is invalid."
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: repo,
      event_source: "action.mark_github_job_complete",
    ).run
  end

  private

  def job_actionable?
    update_job.dotcom_request? && repo.account.active?
  end

  # rubocop:disable Metrics/MethodLength
  def handle_unprocessable(response)
    if response.data.nil?
      increment_error(error_type: :query_error)
      error = response.errors[:data].join(", ")
      case error
      when /401 Unauthorized/
        raise GitHubGraphQL::UnauthorizedError, error
      when /\A5\d{2}/
        raise GitHubGraphQL::ServerError, error
      else
        raise GraphQLQueryError, error
      end
    end

    errors = response.data.
             errors["markRepositoryDependencyUpdateComplete"]

    # We've received an unexpected error structure from GitHub
    if errors.count > 1
      increment_error(error_type: :unexpected_error_count)
      raise errors.join(", ")
    end

    error = errors.first

    case error
    when /Update ID '.*' has already been marked as 'complete'/
      increment_error(error_type: :bad_state)
      raise StateError, error
    when /Update ID '.*' does not exist./
      # RepositoryDependencyUpdate rows are deleted with a Repository
      increment_warning(warning_type: :github_request_gone)
    when /Pull Request #.* does not exist./
      increment_error(error_type: :pull_request_missing)
      raise MissingSubjectError, error
    when /app is not installed/
      increment_error(error_type: :dependabot_not_installed)
      raise GitHubAppError, error
    else
      raise error
    end
  end
  # rubocop:enable Metrics/MethodLength

  def handle_model_errors(errors)
    message = errors.map do |error|
      "#{error.attribute} #{error.short_message}"
    end.join(", ")
    increment_error(error_type: :github_model_error)
    raise GitHubValidationError, message
  end

  def make_graphql_request
    start = Time.now.in_time_zone
    response = GitHubGraphQL.client.query(
      MarkAsCompleteQuery,
      context: {
        account: repo.account,
      },
      variables: {
        databaseId: update_job.github_request_id,
        pullRequestNumber: pull_request.github_number,
      },
    )
    duration = Time.now.in_time_zone - start

    MetricsClient.timing("mark_github_job_complete.graphql_request",
                         duration)

    response
  end

  def increment_error(error_type:)
    update_job.increment_metric(
      "mark_github_job_complete.error",
      tags: { error_type: error_type }
    )
  end

  def increment_warning(warning_type:)
    update_job.increment_metric(
      "mark_github_job_complete.warn",
      tags: { warning_type: warning_type }
    )
  end
end
