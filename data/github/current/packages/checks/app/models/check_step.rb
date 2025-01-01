# typed: true
# frozen_string_literal: true

class CheckStep < ApplicationRecord::Domain::RepositoriesActionsChecks

  include GitHub::FieldTruncator
  include GitHub::Tracing
  include Checks::RepositorySharding

  configure_sharding(should_shard: -> (_, operation) {
    # Only enable sharding key for save operation
    [:save, :save!].include?(operation)
  })

  attribute :name, StringFromBinary.new

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  belongs_to :check_run, inverse_of: :steps

  enum :status, CheckRun.statuses
  enum :conclusion, CheckRun.conclusions

  before_create :copy_repository_id_from_check_run
  before_save :truncate_fields

  validate :matches_check_run_repository

  # Transient field used when getting steps from launch grpc
  attr_accessor :change_id

  MAX_VARBINARY_FIELD_LENGTH = 1024
  ACTIONS_RESULTS_URI_SCHEME = "results"
  HTTP_ERRORS = [
    Faraday::ConnectionFailed,
    URI::InvalidURIError,
    Timeout::Error,
    Errno::EINVAL,
    Errno::ECONNRESET,
    SocketError,
    JSON::ParserError,
  ]

  def self.created_after(time)
    where("created_at > ?", time)
  end

  sig do
    params(
      step: MonolithTwirp::ActionsResults::Core::V1::Step,
      repository_id: Integer,
      check_run_id: Integer
    ).returns(CheckStep)
  end
  def self.from_results_step(step:, repository_id:, check_run_id:)
    CheckStep.new(
      check_run_id:        check_run_id,
      name:                step.name,
      status:              ActionsResults::Utils.to_monolith_status(step.status),
      conclusion:          ActionsResults::Utils.to_monolith_conclusion(step.conclusion),
      started_at:          ActionsResults::Utils.pb_to_time(step.started_at),
      completed_at:        ActionsResults::Utils.pb_to_time(step.completed_at),
      number:              step.number,
      external_id:         step.external_id,
      repository_id:       repository_id,
      completed_log_lines: step.completed_log_lines&.value || 0,
      completed_log_url:   step.completed_log_url&.value || nil,
      change_id:           step.change_order
    )
  end

  def seconds_to_completion
    completed_at = self.completed_at
    if completed_at && started_at && completed_at >= started_at
      (completed_at - started_at).to_i
    end
  end

  def async_readable_by?(actor)
    async_check_run.then do |check_run|
      T.must(check_run).async_repository.then do |repository|
        T.must(repository).async_readable_by?(actor)
      end
    end
  end

  def authenticated_completed_log_url
    return nil unless completed_log_url

    run = T.must(check_run)
    repo = T.must(run.repository)

    UrlHelpers.check_step_logs_path(repository: repo,
                                                              user_id: T.must(repo.owner).display_login,
                                                              ref: run.head_sha,
                                                              id: run.id,
                                                              step: number)
  end

  def skipped?
    conclusion == "skipped"
  end

  def completed?
    conclusion.present?
  end

  def completed_without_logs?
    completed? && completed_log_url.nil?
  end

  # Allows for easier testing when stubbing/mocking twirp methods
  def to_proto_object
    proto_step = MonolithTwirp::ActionsResults::Core::V1::Step.new(
      external_id: external_id,
      name: name,
      status: ActionsResults::Utils.to_results_status(status),
      number: number,
    )

    if conclusion.present?
      proto_step.conclusion = ActionsResults::Utils.to_results_conclusion(conclusion)
    end

    if started_at.present?
      proto_step.started_at = Google::Protobuf::Timestamp.new(seconds: started_at.to_i)
    end

    if completed_at.present?
      proto_step.completed_at = Google::Protobuf::Timestamp.new(seconds: completed_at.to_i)
    end

    if completed_log_url.present?
      proto_step.completed_log_url = Google::Protobuf::StringValue.new(value: completed_log_url)
    end

    if completed_log_lines.present?
      proto_step.completed_log_lines = Google::Protobuf::Int64Value.new(value: completed_log_lines)
    end

    proto_step
  end

  def get_signed_completed_log_url
    return nil if completed_log_url.blank?

    is_results = ActionsResults::Utils.is_results_url?(completed_log_url)

    if is_results
      # results://
      get_completed_log_url_from_results(completed_log_url)
    else
      # http:// or https://
      get_completed_log_url_from_actions_service(completed_log_url)
    end
  rescue *HTTP_ERRORS => e
    GitHub.dogstats.increment("actions.workflow_job_run.get_signed_completed_log_url.error", tags: ["error:#{T.must(e.class.name).underscore}", "is_results:#{is_results}"])
    Failbot.report(e)
    nil
  end

  # retrieve the signed completed step log URL from actions service through Launch
  def request_completed_log_url_from_actions_service(unauthenticated_url)
    check_suite = T.must(T.must(check_run).check_suite)
    Launch::Twirp::artifacts_exchange_client_for_check_suite(check_suite)
      .exchange_url_for(
        unauthenticated_url:,
        repository: T.must(check_suite.repository),
        resource_type: Launch::Twirp::ResourceType::COMPLETED_STEP_LOG
      )
  end

  private

  # Request completed step log from the results service:
  # 1. Parse the results:// URI to obtain the workflow run ID and workflow job run ID
  # 2. Make a Twirp request to results-core to retrieve the completed step log URL
  # 3. If the Twirp call made in (2) is successful return the log URL
  # 4. If the Twirp call made in (2) fails, fallback to the actions service URL in the query params
  # 5. :)
  def get_completed_log_url_from_results(url)
    return nil unless url

    # the summary URI sent from the Results service will
    # be of the form: results://actions-results/run/<workflow run ID>/job/<workflow job run ID>
    matches = ActionsResults::Utils.get_ids_from_results_url(url)
    return nil unless matches

    res = ActionsResults::Twirp.log_client.get_completed_step_log_url(
      workflow_job_run_backend_id: T.must(matches[:workflow_job_run_backend_id]),
      workflow_run_backend_id: T.must(matches[:workflow_run_backend_id]),
      step_backend_id: T.must(matches[:step_backend_id]),
    )

    if !res.call_succeeded? || !res.value.log_url.present?
      GitHub.dogstats.increment("actions.workflow_job_run.get_completed_log_url_from_results.fallback_to_actions_service", tags: ["status_code:#{res.status}"])
      return fallback_to_actions_service(url)
    end

    res.value.log_url
  end

  # If a call fails to results service to download logs, we will fallback to the actions service URL in the query params
  # for more information see https://github.com/github/actions-results/pull/467
  def fallback_to_actions_service(url)
    actions_service_url = ActionsResults::Utils.actions_url(url)

    return nil if actions_service_url.nil?

    get_completed_log_url_from_actions_service(actions_service_url)
  end

  # request to retrieve the signed
  # completed step log URL from actions service through Launch
  def get_completed_log_url_from_actions_service(url)
    return nil if url.blank?

    result = request_completed_log_url_from_actions_service(url)

    if result.call_succeeded?
      GitHub.dogstats.increment("actions.exchange_url_request.succeeded", tags: ["step_logs"])

      result.value.authenticated_url
    else
      GitHub.dogstats.increment("actions.exchange_url_request.failed", tags: ["step_logs"])

      nil
    end
  end

  def matches_check_run_repository
    check_run = self.check_run
    if check_run && repository_id && repository_id != check_run.repository_id
      errors.add(:repository, "does not match the check run's repository")
    end
  end

  def copy_repository_id_from_check_run
    self.repository_id = T.must(check_run).repository_id
  end

  def truncate_fields
    truncate_field(:name, MAX_VARBINARY_FIELD_LENGTH)
  end
end
