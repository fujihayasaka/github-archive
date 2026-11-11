# frozen_string_literal: true

# Enables auto merge on a pull request
class EnableAutoMerge
  class GraphQLQueryError < StandardError; end
  class GitHubValidationError < StandardError; end
  class MissingSubjectError < StandardError; end

  class EnableAutoMergeResult
    ALLOWED_OUTCOMES = [
      :success, # Auto merge enabled successfully
      :clean, # The branch can be merged, so auto merge was not enabled
      :error, # An error occurred but we can show the message to the user
    ].freeze

    attr_reader :message

    def initialize(outcome:, message: nil)
      unless ALLOWED_OUTCOMES.include?(outcome)
        raise ArgumentError, "outcome must be one of #{ALLOWED_OUTCOMES.join(', ')}"
      end

      @outcome = outcome

      raise ArgumentError, "message must be provided when outcome is :error" if outcome == :error && message.nil?

      @message = message
    end

    def success?
      @outcome == :success
    end

    def clean?
      @outcome == :clean
    end

    def error?
      @outcome == :error
    end
  end

  EnableAutoMergeQuery = GitHubGraphQL.client.parse <<-'GRAPHQL'
    mutation($pullRequestId: ID!, $mergeMethod: PullRequestMergeMethod!) {
      enablePullRequestAutoMerge(input: { pullRequestId: $pullRequestId, mergeMethod: $mergeMethod }) {
        actor {
          login
        }
      }
    }
  GRAPHQL

  attr_reader :pull_request

  def initialize(pull_request:, squash: false)
    @pull_request = pull_request
    @squash = squash
  end

  def run
    # The GraphQL response can return errors in 3 ways:
    # * authorization error as a top-level key
    # * query error as sub-key of data
    # * model error as a sub-key of the queried object
    #
    # We convert the response to a hash to make error processing consistent across the three types.
    response = make_graphql_request(pull_request).to_h

    Dependabot::Logger.info(
      "code.namespace": "EnableAutoMergeOnPullRequest",
      response: response.to_json,
      **pull_request.telemetry_attributes,
    )

    if (data = response.dig("data", "enablePullRequestAutoMerge"))
      errors = data["errors"]
      handle_model_errors(errors) unless errors.nil?
      return EnableAutoMergeResult.new(outcome: :success)
    end

    return_value = handle_unprocessable(response)
    # protect against accidentally forgetting to return a value in the future
    raise "EnableAutoMerge#run must return a value or raise" if return_value.nil?

    return_value
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
    when /Pull request is in clean status/
      EnableAutoMergeResult.new(outcome: :clean)
    else
      # The error messages repeat themselves, remove the first "Pull request" if it exists
      message = error_message.delete_prefix("Pull request ")
      # Sometimes it's doubled up in the middle of the error message
      message = message.gsub("Pull request Pull request", "Pull request")
      EnableAutoMergeResult.new(outcome: :error, message: message)
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
      EnableAutoMergeQuery,
      context: {
        account: pull_request.repo.account,
      },
      variables: {
        pullRequestId: get_pull_request_id(pull_request),
        mergeMethod: @squash ? "SQUASH" : "MERGE",
      }
    )
    duration = Time.now.in_time_zone - start

    MetricsClient.timing("enable_auto_merge_query.graphql_request", duration)

    response
  end

  def get_pull_request_id(pull_request)
    GetPullRequestId.new(pull_request: pull_request).run
  end

  def increment_error(error_type:)
    MetricsClient.increment(
      "enable_auto_merge_on_pull_request.error",
      tags: { error_type: error_type }
    )
  end
end
