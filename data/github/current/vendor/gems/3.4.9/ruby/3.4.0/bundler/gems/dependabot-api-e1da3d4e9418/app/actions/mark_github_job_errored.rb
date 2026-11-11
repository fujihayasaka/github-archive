# frozen_string_literal: true

# Marks the originating RepositoryDependencyUpdate object in GitHub as errored
# with user-visible error content for the Repository's Alert screen.
class MarkGitHubJobErrored
  class GitHubValidationError < StandardError; end

  class GitHubAppError < StandardError; end

  class MissingSubjectError < StandardError; end

  class StateError < StandardError; end

  class GraphQLQueryError < StandardError; end

  MarkAsErroredQuery = GitHubGraphQL.client.parse <<-'GRAPHQL'
    mutation($databaseId: Int!, $errorTitle: String!, $errorBody: String!, $errorType: String) {
      markRepositoryDependencyUpdateErrored(input: { databaseId: $databaseId, errorTitle: $errorTitle, errorBody: $errorBody, errorType: $errorType }) {
        errors {
          attribute
          shortMessage
        }
      }
    }
  GRAPHQL

  attr_reader :update_job, :repo, :error_presenter

  DEFAULT_ERROR_HASH = {
    "error-type" => "unknown_error",
  }.freeze

  def initialize(update_job:, error_hash: DEFAULT_ERROR_HASH)
    @update_job = update_job
    @repo = update_job.update_config.repo
    @error_presenter = UpdateJobErrorPresenter.new(
      error_hash: error_hash,
      update_job: update_job,
    )
  end

  # rubocop:disable Metrics/PerceivedComplexity
  def run
    return false if update_job.dry_run?

    # If we don't have a github request id, there's no way to associate this
    # update job back to a record in the github database
    return false unless update_job.github_request_id
    return false unless repo.account.active?

    response = make_graphql_request

    if (data = response.data&.mark_repository_dependency_update_errored)
      errors = data.errors
      handle_model_errors(errors) if errors.any?
      update_job.increment_metric("mark_github_job_errored.success")
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
      event_source: "action.mark_github_job_errored",
    ).run
  end
  # rubocop:enable Metrics/PerceivedComplexity

  private

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
             errors["markRepositoryDependencyUpdateErrored"]

    # We've received an unexpected error structure from GitHub
    if errors.count > 1
      increment_error(error_type: :unexpected_error_count)
      raise errors.join(", ")
    end

    error = errors.first

    case error
    when /cannot be marked as errored as it is currently '(complete|error)'/,
         /has already received an error/
      increment_error(error_type: :bad_state)
      raise StateError, error
    when /does not exist/
      # RepositoryDependencyUpdate rows are deleted with a Repository
      increment_warning(warning_type: :github_request_gone)
    when /app is not installed/
      increment_error(error_type: :dependabot_not_installed)
      raise GitHubAppError, error
    else
      increment_error(error_type: :unknown)
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
      MarkAsErroredQuery,
      context: {
        account: repo.account,
      },
      variables: {
        databaseId: update_job.github_request_id,
        errorTitle: error_presenter.issue_title,
        errorBody: error_presenter.issue_body,
        errorType: error_presenter.issue_type,
      },
    )
    duration = Time.now.in_time_zone - start

    MetricsClient.timing("mark_github_job_errored.graphql_request",
                         duration)

    response
  end

  def increment_error(error_type:)
    update_job.increment_metric(
      "mark_github_job_errored.error",
      tags: { error_type: error_type }
    )
  end

  def increment_warning(warning_type:)
    update_job.increment_metric(
      "mark_github_job_errored.warn",
      tags: { warning_type: warning_type }
    )
  end
end
