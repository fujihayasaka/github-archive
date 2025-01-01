# typed: true
# frozen_string_literal: true

class CheckRun < ApplicationRecord::Domain::RepositoriesActionsChecks
  include GitHub::ResilienceMixin

  serialize :images, type: Array
  serialize :actions, type: Array, yaml: { permitted_classes: ActiveRecord.yaml_column_permitted_classes + [CheckRunAction] }

  include CheckRun::ActionsDependency
  include CheckRun::CodeScanningDependency
  include GitHub::FieldTruncator
  include GitHub::Validations
  include GitHub::Relay::GlobalIdentification
  include GitHub::Tracing
  include Instrumentation::Model
  include Checks::RepositorySharding
  include Repositories::BelongsToRepository

  configure_sharding(should_shard: -> (_, operation) {
    [:save, :save!].include?(operation) # Only enabling sharding key for save operation
  })

  attribute :name, StringFromBinary.new
  attribute :summary, Checks::MaybeCompressed.new(self, :summary)
  attribute :text, Checks::MaybeCompressed.new(self, :text)
  attribute :title, StringFromBinary.new
  attribute :display_name, StringFromBinary.new

  MAX_CHECK_RUNS_PER_NAME = 1_000

  MAX_VARBINARY_FIELD_LENGTH = 1024

  MAX_CHECK_SUITE_LIMIT_ON_SHA = 1000

  belongs_to :check_suite, inverse_of: :check_runs
  belongs_to :creator, class_name: "User"
  belongs_to_repository_via_domain optional: false, return_type: T.nilable(Repository) # TODO: Update to Repositories::IRepository


  # TODO: we currently don't set a value to this field in the db
  # and we do delegate `github_app` to the check_suite. Keeping here temporarily
  # until we decide what the longer term approach should be.
  # belongs_to :github_app, :foreign_key => :performed_via_app_id, :class_name => "Integration"
  has_many :annotations, class_name: "CheckAnnotation", inverse_of: :check_run
  destroy_dependents_in_background :annotations, sharding_key: :repository_id, sharding_value_key: :repository_id

  has_many :steps,
    -> (check_run) { where(repository_id: check_run.repository_id).order(:number) },
    class_name: "CheckStep",
    inverse_of: :check_run,
    autosave: :true
  destroy_dependents_in_background :steps

  has_many :gate_requests, -> { includes(:gate) }
  destroy_dependents_in_background :gate_requests

  has_one :deployment

  has_one :workflow_job_run,
    ->(check_run) { where(repository_id: check_run.repository_id) },
    class_name: "Actions::WorkflowJobRun",
    inverse_of: :check_run

  # Notes on enum values:
  # - When creating/updating a CheckRun through the API, clients can choose from only "queued", "in_progress", or "completed"[0]
  # - "completed" is the only terminal state, i.e. all CheckRuns will eventually converge to "completed"
  # - "requested", "waiting", and "pending" are only used by Actions
  # - "waiting" comes right after "requested". Though it is marked at "3", we will honor that while calculating rollup
  #
  # [0]: https://docs.github.com/rest/checks/runs#update-a-check-run--parameters
  #
  #
  # These statuses are also being used by git-src-migrator to monitor the status of dynamic workflows in
  # app/api/internal/twirp/git_src_migrator/monolith/v1/git_src_migrator_workflow_api_handler.rb
  # Please let the Migration Tools team know if you add/remove any statuses
  enum :status, {
    requested: -1,  # Actions-only. CheckRun has been created but a job has not yet been queued within the actions service
    queued: 0,      # CheckRun will be processed, but is not known to have started yet. (this is the column default)
    in_progress: 1, # CheckRun is currently being processed
    completed: 2,   # CheckRun has finished, i.e. it has a `conclusion`
    waiting: 3,     # Actions-only. Job is waiting on a [gate state](https://github.com/github/c2c-actions/blob/7729e3e/docs/adrs/1683-add-waiting-status-to-checkrun.md)
    pending: 4,     # Actions-only. Job is waiting for [group-based concurrency](https://github.com/github/c2c-actions/blob/7729e3e/docs/adrs/2340-add-pending-state-for-checks.md)
  }
  enum :conclusion, {
    neutral: 0,
    success: 1,
    failure: 2,
    cancelled: 3,
    action_required: 4,
    timed_out: 5,
    skipped: 6,
    stale: 7,
  }

  IMAGES_BYTESIZE_LIMIT = 65_535
  TEXT_BYTESIZE_LIMIT = 65_535
  MAX_ACTIONS_QUANTITY = 3

  SUMMARY_BYTESIZE_LIMIT = 65_535

  # MAX_NUMBER_VALUE = 2147483647, the size of a INT(11) value in MySQL
  # Calculated by getting the biggest value for 32bits, divided by 2 to get the max signed value
  # and substracting one
  MAX_NUMBER_VALUE = (1 << 32) / 2 - 1

  ACTIONS_RESULTS_URI_SCHEME = "results".freeze
  HTTP_ERRORS = [
    Faraday::ConnectionFailed,
    URI::InvalidURIError,
    Timeout::Error,
    Errno::EINVAL,
    Errno::ECONNRESET,
    SocketError,
    JSON::ParserError,
  ]

  validates_presence_of :status
  validates_presence_of :conclusion, if: -> { T.unsafe(self).completed_at.present? }
  validates_presence_of :conclusion, if: :completed?
  validates :external_id, unicode3: true

  validate :images_format_and_size_is_valid, on: [:create, :update]
  validate :size_of_summary, on: [:create, :update]
  validate :details_url_is_valid, on: [:create, :update]
  validate :matches_check_suite_repository

  validates_length_of :actions, maximum: MAX_ACTIONS_QUANTITY, message: "exceeds a maximum quantity of #{MAX_ACTIONS_QUANTITY}"

  delegate :head_sha, :github_app, :commit, to: :check_suite
  alias_method :integration, :github_app

  before_validation :convert_images_to_normal_hashes
  before_create :normalize_name
  before_save :instrument_status_changed
  after_commit :instrument_workflow_job_run_create, on: :create
  after_commit :instrument_workflow_job_run_update, on: :update
  before_save :set_started_at
  before_save :set_status_completed, if: -> { T.unsafe(self).concluded? && !T.unsafe(self).completed? }
  before_save :assign_completed_at, if: -> { T.unsafe(self).concluded? && T.unsafe(self).completed_at.blank? }
  before_save :completed_at_not_in_future
  before_save :truncate_fields

  after_create :create_workflow_job_run
  after_commit :instrument_creation, on: :create
  after_commit :instrument_completion, on: [:create, :update]
  after_commit :update_suite_rollups, on: [:create, :update]
  after_commit :notify_socket_subscribers, on: [:create, :update]
  after_commit :delete_previous_check_runs, on: :create
  after_commit :call_auto_merge_job_enqueuer, on: [:update, :create], if: :concluded?

  trace_method :update_suite_rollups
  trace_method :notify_socket_subscribers
  trace_method :delete_previous_check_runs
  trace_method :create_workflow_job_run
  trace_method :call_auto_merge_job_enqueuer
  trace_method :instrument_workflow_job_run_update
  trace_method :latest_for_sha_and_event_in_repository

  scope :for_sha_and_repository_id, ->(shas, repo_id) {
    joins("INNER JOIN check_suites ON check_suites.id = check_runs.check_suite_id").
    where("check_suites.head_sha IN (:shas) AND check_runs.repository_id = :repo_id", { shas: shas, repo_id: repo_id })
  }
  # SCIENCE EXPERIMENT CANDIDATE
  scope :for_sha_and_repository_id_candidate, ->(shas, repo_id) {
    joins("INNER JOIN check_suites as check_suites_for_repo_and_sha ON check_suites_for_repo_and_sha.id = check_runs.check_suite_id").
    where("check_suites_for_repo_and_sha.repository_id = :repo_id AND check_suites_for_repo_and_sha.head_sha IN (:shas) AND check_runs.repository_id = :repo_id", { shas: shas, repo_id: repo_id })
  }
  scope :for_app_id, ->(id, repo_id) {
    joins("INNER JOIN check_suites as check_suites_for_app ON check_suites_for_app.id = check_runs.check_suite_id AND check_suites_for_app.repository_id = check_runs.repository_id").
    where("check_suites_for_app.github_app_id = :app_id OR (check_suites_for_app.github_app_id = :app_id AND check_runs.repository_id = :repo_id)", { app_id: id.to_i, repo_id: repo_id })
  }
  scope :for_repository_id_and_check_suite_ids, ->(repo_id, check_suite_ids) {
    joins("INNER JOIN check_suites ON check_suites.id = check_runs.check_suite_id").
    where("check_suites.id IN (:check_suite_ids) AND check_runs.repository_id = :repo_id AND check_suites.repository_id = :repo_id", { check_suite_ids: check_suite_ids, repo_id: repo_id })
  }
  scope :concluded, -> { where.not(conclusion: nil) }
  scope :with_display_name, ->(display_name) { where(display_name: display_name) }

  # Get check runs that completed and are considered failures (ones that #failed? will return true for).
  scope :failed, -> { completed.where(conclusion: StatusCheckConfig::FAILURE_AND_INCOMPLETE_STATES) }

  # Transient fields that will be assigned to the workflow job
  # after the check run is created
  attr_accessor :job_key, :parent_job_id, :concurrency, :labels, :runner_id, :runner_name, :runner_group_id, :runner_group_name, :is_cloned_from_previous_run, :summary_url

  # Retrieve Check names that have been posted to the repository
  # recently, and the Integrations that were used to create them.
  #
  # Returns a Hash of Sets of Strings.
  sig { params(repo: Repository, start: Time, limit: Integer).returns(T::Hash[String, T::Set[Integration]]) }
  def self.recent_check_names_and_integrations(repo:, start:, limit:)
    results = CheckRun
      .joins(:check_suite)
      .joins("LEFT JOIN workflow_runs ON check_suite.id = workflow_runs.check_suite_id")
      .where(check_suite: { repository: repo, is_archived: false, updated_at: start.. })
      .where(workflow_runs: { imposer_repository_id: [0, nil] }) # ignore required workflows
      .where(check_runs: { completed_at: start.. }) # This maintains the same behavior as the old method - probably not needed but doesn't seem to negatively impact performance
      .order(check_suite: { updated_at: :desc })
      .limit(limit)
      .distinct
      .pluck(Arel.sql("COALESCE(check_runs.display_name, check_runs.name)"), "check_suite.github_app_id")

    integrations_by_id = Integration.includes(:bot).where(id: results.map(&:second).compact.uniq).group_by(&:id)

    results.each_with_object({}) do |(name, integration_id), results|
      name = GitHub::Encoding.try_guess_and_transcode(name)
      results[name] ||= Set.new
      if integrations_by_id.has_key?(integration_id)
        results[name].merge(integrations_by_id[integration_id])
      end
    end
  end

  # Fetch the ids of every check suite's most recent CheckRun per sha and repository id
  #
  # Returns array of CheckRun ids.
  def self.latest_ids_for_sha_and_repository(shas, repository)
    binds = {
        head_shas: Array(shas),
        repository_id: repository.id,
    }

    self.connection.select_values(Arel.sql(<<-SQL, **binds))
      SELECT MAX(check_runs.id) AS check_run_id
        FROM check_runs
          JOIN check_suites
          ON check_runs.check_suite_id = check_suites.id
        WHERE check_suites.head_sha IN (:head_shas)
          AND check_runs.repository_id = :repository_id
          AND (check_suites.workflow_file_path IS NULL OR check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at))
          GROUP BY check_runs.name, check_runs.check_suite_id
    SQL
  end

  def self.latest_for_sha_and_event_in_repository(shas, repository)
    binds = {
        head_shas: Array(shas),
        repository_id: repository.id,
    }

    check_suite_ids = self.connection.select_values(Arel.sql(<<-SQL, **binds))
      SELECT MAX(check_suites.id)
        FROM check_suites
        WHERE check_suites.head_sha IN (:head_shas)
          AND check_suites.repository_id = :repository_id
          AND check_suites.hidden = FALSE
          AND check_suites.workflow_file_path IS NOT NULL
        GROUP BY check_suites.github_app_id, check_suites.workflow_file_path, check_suites.event, check_suites.head_sha

      UNION

      SELECT check_suites.id
        FROM check_suites
        WHERE check_suites.head_sha IN (:head_shas)
          AND check_suites.repository_id = :repository_id
          AND check_suites.workflow_file_path IS NULL
    SQL

    return none if check_suite_ids.empty?

    check_run_ids = self.connection.select_values(Arel.sql(<<-SQL, ids: check_suite_ids, repository_id: repository.id))
      SELECT MAX(check_runs.id) AS check_run_id
      FROM check_runs
        JOIN check_suites
        ON check_runs.check_suite_id = check_suites.id
      WHERE check_runs.check_suite_id IN (:ids)
        AND check_suites.repository_id = :repository_id
        AND (check_suites.workflow_file_path IS NULL
          OR check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at))
        AND check_runs.repository_id = :repository_id
      GROUP BY check_runs.name, check_runs.check_suite_id
    SQL

    where(id: check_run_ids, repository_id: repository.id)
  end

  # Fetch every check suite's most recent CheckRun per sha and repository
  #
  # Returns ActiveRecord::Relation
  def self.latest_for_sha_and_repository(shas, repository)
    ids = latest_ids_for_sha_and_repository(shas, repository)

    where(id: ids, repository_id: repository.id)
  end

  # Returns an array of check_runs
  def self.check_runs_at_merge(repository:, sha:, merged_at:)
    ids = science "checksuite-repoid-query-five-check-runs-at-merge" do |e|
      e.context({
        repository_id: repository.id,
        sha: sha,
        merged_at: merged_at,
      })

      e.use do
        self.connection.select_values(Arel.sql(<<-SQL, repository_id: repository.id, sha: sha, merged_at: merged_at))
          SELECT MAX(check_runs.id)
          FROM check_runs
            JOIN check_suites
            ON check_runs.check_suite_id = check_suites.id
          WHERE check_suites.head_sha = :sha
            AND check_runs.repository_id = :repository_id
            AND check_runs.created_at < :merged_at
          GROUP BY check_runs.name, check_runs.check_suite_id
        SQL
      end
      e.try do
        self.connection.select_values(Arel.sql(<<-SQL, repository_id: repository.id, sha: sha, merged_at: merged_at))
          SELECT MAX(check_runs.id)
          FROM check_runs
            JOIN check_suites
            ON check_runs.check_suite_id = check_suites.id
          WHERE check_suites.head_sha = :sha
            AND check_suites.repository_id = :repository_id
            AND check_runs.repository_id = :repository_id
            AND check_runs.created_at < :merged_at
          GROUP BY check_runs.name, check_runs.check_suite_id
        SQL
      end

      e.compare do |control, candidate|
        control.to_set == candidate.to_set
      end
    end

    where(id: ids, repository_id: repository.id)
  end

  # Separate function so easier to stub tests
  def self.default_max_check_suites_per_sha_limit
    MAX_CHECK_SUITE_LIMIT_ON_SHA
  end

  def self.latest_ids_with_annotations_for_sha_and_repository_with_limit(sha, repository, check_suite_evaluation_limit)
    most_recent_check_suites = CheckSuite.most_recent_check_suites_for_sha(repository.id, sha, check_suite_evaluation_limit)
    check_suite_ids = most_recent_check_suites.pluck(:id)

    binds = {
      head_sha: sha,
      repository_id: repository.id,
      check_suite_ids: check_suite_ids
    }

    sql = Arel.sql(<<-SQL, **binds)
    SELECT MAX(check_runs.id) AS check_run_id
      FROM check_runs
        JOIN check_suites ON check_runs.check_suite_id = check_suites.id AND check_suites.repository_id = :repository_id
        JOIN check_annotations ON check_runs.id = check_annotations.check_run_id AND check_annotations.repository_id = :repository_id AND check_annotations.check_suite_id IS NULL
  SQL

    if most_recent_check_suites.length == check_suite_evaluation_limit
      sql += Arel.sql(<<-SQL, **binds)
      WHERE check_suites.id IN (:check_suite_ids)
  SQL
    else
      sql += Arel.sql(<<-SQL, **binds)
        WHERE check_suites.head_sha = :head_sha
  SQL
    end

    sql += Arel.sql(<<-SQL, **binds)
        AND check_runs.repository_id = :repository_id
        AND (check_suites.workflow_file_path IS NULL OR check_runs.created_at >= IFNULL(check_suites.started_at, check_suites.created_at))
        GROUP BY check_runs.name, check_runs.check_suite_id
  SQL

    self.connection.select_values(sql)
  end

  # In certain scenarios fetching all check runs for a sha can be expensive and lead to timeouts since there can be an undounded amount of check suites on a single
  # sha due to scheduled, worfklow_dispatch events or other automation users have set up. This limits the total number of check runs returned, see https://github.com/github/c2c-actions-checks/issues/1631
  def self.for_sha_and_repository_id_with_limit(repository_id, sha, check_suite_evaluation_limit)
    most_recent_check_suites = CheckSuite.most_recent_check_suites_for_sha(repository_id, sha, check_suite_evaluation_limit)
    if most_recent_check_suites.length == check_suite_evaluation_limit
      check_suite_ids = most_recent_check_suites.pluck(:id)
      CheckRun.for_repository_id_and_check_suite_ids(repository_id, check_suite_ids)
    else
      CheckRun.for_sha_and_repository_id(sha, repository_id).to_a
    end
  end

  # The GitHub web URL for details about this CheckRun.
  #
  # pull - A PullRequest instance. If present, returns the pull request permalink
  #
  # Examples:
  #
  #   check_run.permalink
  #   # => `/github/github/runs/4
  #
  #   check_run.permalink(pull: pull)
  #   # => /github/github/pulls/1/checks?check_run_id=2
  #
  # TODO this can be improved by passing in a workflow run ID so that the workflow_job_run doesn't have to be fetched during link generation. In most places this can be done.
  def permalink(pull: nil, include_host: nil, check_suite_focus: false, pull_request: nil, repo: nil)
    pull_request ||= pull
    repo ||= repository

    # Always direct users to the new Actions-specific UI, even when they navigate from a PR
    if is_actions_check_run?
      # potentially if there is high replication lag with the repositories-actions-checks DB, a check_run may be missing a workflow_job run so differ to the old route
      workflow_job_run = self.workflow_job_run
      if workflow_job_run.present?
        if pull_request
          return "#{repo.permalink(include_host: include_host)}/actions/runs/#{workflow_job_run.workflow_run_id}/job/#{id}?pr=#{pull_request.number}"
        else
          return "#{repo.permalink(include_host: include_host)}/actions/runs/#{workflow_job_run.workflow_run_id}/job/#{id}"
        end
      else
        if pull_request
          return "#{repo.permalink(include_host: include_host)}/runs/#{id}?check_suite_focus=true&pr=#{pull_request.number}"
        else
          return "#{repo.permalink(include_host: include_host)}/runs/#{id}?check_suite_focus=true"
        end
      end
    end

    if pull_request
      "#{pull.permalink(include_host: false)}/checks?check_run_id=#{id}"
    elsif check_suite_focus
      "#{repo.permalink(include_host: include_host)}/runs/#{id}?check_suite_focus=true"
    else
      "#{repo.permalink(include_host: include_host)}/runs/#{id}"
    end
  end

  def event_payload
    repository = T.must(self.repository)
    {
      event_prefix => self,
      :primary_resource => self.attributes,
      :repository_id => repository_id,
      :organization_id => repository.organization&.id,
      :business_id => repository.organization&.business&.id
    }
  end

  def creator
    super || User.ghost
  end

  def duration
    completed_at = self.completed_at
    return 0 unless completed_at

    (completed_at - (started_at || completed_at)).floor
  end

  def instrument_status_changed
    return if workflow_job_run&.cloned_from_previous_run?
    return unless status_changed? || conclusion_changed?
    return if new_record?

    GlobalInstrumenter.instrument "check_run.status_changed", {
        check_run_id: id,
        previous_status: status_was,
        current_status: status,
        previous_conclusion: conclusion_was,
        current_conclusion: conclusion,
    }
  end

  def instrument_workflow_job_run_create
    instrument_workflow_job_run_event
  end

  def instrument_workflow_job_run_update
    return unless saved_change_to_attribute?(:status)
    instrument_workflow_job_run_event
  end

  def instrument_workflow_job_run_event
    workflow_job_run = self.workflow_job_run
    repository = T.must(self.repository)

    return unless workflow_job_run
    return if workflow_job_run.cloned_from_previous_run?
    return unless self.check_suite.present?

    event_key = case status.to_sym
    when :waiting, :queued, :in_progress, :completed
      status.to_sym.to_s
    end

    if event_key
      workflow_job_run = T.must(self.workflow_job_run)
      payload = {
        action: event_key,
        prefix: "workflow_job",
        job_id: workflow_job_run.id,
        repository_id: self.repository_id,
        primary_resource: workflow_job_run.attributes
      }

      ActiveRecord::Base.connected_to(role: :reading) do
        repository = T.must(self.repository)
        payload[:actor_id] = T.must(self.check_suite).creator&.id
        payload[:organization_id] = repository.organization&.id
        payload[:business_id] = repository.organization&.business&.id
      end

      instrument event_key, payload
    end
  end

  def instrument_creation
    # is_cloned_from_previous_run is a transient field used during creation. Using this boolean here since it is a callback for create
    # Other parts of the check_run lifecycle should use the workflow_job_run to determine if a check_run is cloned
    return if is_cloned_from_previous_run
    instrument :create
  end

  def instrument_completion
    return if workflow_job_run&.cloned_from_previous_run?
    instrument :complete if concluded? && saved_change_to_attribute?(:conclusion)
  end

  def rerequest(actor:)
    instrument :rerequest, event_payload.merge(actor_id: actor.id)

    T.must(check_suite).reset
  end

  # Has this CheckRun concluded?
  #
  # Returns a boolean.
  def concluded?
    conclusion.present?
  end

  def required_for_pull_request?(pull)
    async_required_for_pull_request?(pull).sync
  end

  def async_required_for_pull_request?(pull)
    return Promise.resolve(false) unless policy_evaluator = pull.base_branch_rule_evaluator
    return Promise.resolve(false) unless policy_evaluator.required_status_checks_enabled?

    policy_evaluator.async_has_required_status_check?(visible_name)
  end

  def async_text
    Platform::Loaders::CheckRunText.load(self.id, column: :text, repository_id: T.must(T.must(check_suite).repository).id)
  end

  def async_summary
    Platform::Loaders::CheckRunText.load(self.id, column: :summary, repository_id: T.must(T.must(check_suite).repository).id)
  end

  def self.latest_version_of(check_run, repository_id)
    binds = {
        name: GitHub::SQL::ArelLiterals.binary(check_run.name),
        check_suite_id: check_run.check_suite_id,
        repo_id: repository_id
    }

    id = self.connection.select_value(Arel.sql(<<-SQL, **binds))
      SELECT `check_runs`.id FROM `check_runs`
      LEFT JOIN check_runs cr2 ON (
        check_runs.check_suite_id = cr2.check_suite_id
        AND check_runs.name = cr2.name
        AND check_runs.id < cr2.id)
      WHERE `check_runs`.`name` = :name
      AND `check_runs`.`repository_id` = :repo_id
      AND `check_runs`.`check_suite_id` = :check_suite_id
      AND cr2.id IS NULL
    SQL

    find(id)
  end

  def details_url
    return @details_url if defined?(@details_url)
    @details_url = begin
      if check_suite&.actions_app? || check_suite&.code_scanning_app?
        permalink(include_host: true)
      else
        self[:details_url] || check_suite&.github_app&.url
      end
    end
  end

  def request_action(actor:, requested_action:)
    instrument :request_action, event_payload.merge(
        actor_id: actor.id,
        requested_action: requested_action,
        )
  end

  def annotation_count
    @annotation_count ||= annotations.count
  end

  def sort_order
    state = (conclusion || status).to_s
    [number || MAX_NUMBER_VALUE, StatusCheckConfig::STATE_SORT_ORDER[state], contextual_name]
  end

  def failed?
    # Keep in sync with `CheckRun.failed` scope
    status == "completed" && StatusCheckConfig::FAILURE_AND_INCOMPLETE_STATES.include?(conclusion)
  end

  def successful?
    status == "completed" && StatusCheckConfig::SUCCESS_STATES.include?(conclusion)
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_repository.then do |repo|
      path_uri = T.must(repo).path_uri.dup
      path_uri.path += "/runs/#{id}"
      path_uri
    end
  end

  def commit_channel
    GitHub::WebSocket::Channels.commit(T.must(check_suite).repository, T.must(check_suite).head_sha)
  end

  def gates_channel
    GitHub::WebSocket::Channels.actions_gate_requests(T.must(check_suite).workflow_run)
  end

  def channel
    GitHub::WebSocket::Channels.check_run(self)
  end

  def async_readable_by?(actor)
    async_repository.then do |repository|
      T.must(repository).async_readable_by?(actor)
    end
  end

  # Internal: Since `actions` is serialized, we can't check if it is valid without deserializing.
  def valid?(*)
    # Added `action.is_a?(CheckRunAction)` because there are some outdated actions which were
    # serialized in an inconsistent form.
    super && actions.all? do |action|
      if action.is_a?(CheckRunAction)
        action.valid?
      else
        err = ArgumentError.new("CheckRunAction was a #{action.class} instead of a CheckRunAction")
        Failbot.report(err, "gh.check_run.id": id)
        false
      end
    end
  end

  def log_update_suite_rollups(at, more_attrs = {})
    payload = {
      "code.namespace" => self.class.name,
      "code.function" => "log_update_suite_rollups",
      "job" => "UpdateSuiteRollups",
    }
    payload.merge!(log_object)
    payload.merge!(T.must(check_suite).log_object)
    payload.merge!(more_attrs)
    GitHub.logger.info(at, payload)
  end

  def seconds_to_completion
    completed_at = self.completed_at
    if completed_at && started_at && completed_at >= started_at
      (completed_at - started_at).to_i
    end
  end

  # check run name as shown in the merge box
  # and dropdowns that show the list of contexts (statuses and check runs)
  # potential for no check_suite if there is very high replication lag and associated check_suite is not present in replica
  def contextual_name
    full_name = visible_name
    check_suite = self.check_suite
    if check_suite.present?
      full_name = "#{check_suite.name} / #{full_name}" if check_suite.name
      full_name = "#{full_name} (#{check_suite.event})" if check_suite.event
    end
    full_name
  end

  def visible_name
    display_name || name
  end

  def completed_without_logs?
    completed? && completed_log_url.nil?
  end

  # HashWithIndifferentAccess is the default type that gets given to us by the API.
  # It also takes much more space than a normal Hash when serialized to a text column.
  # Due to this, we force all hashes to be normal hashes with symbolized keys to keep data size low in the DB
  def convert_images_to_normal_hashes
    self.images = self.images.map { |i| i.to_hash.deep_symbolize_keys }
  end

  # Resets values in this check_run and check_steps used to store logs
  def delete_logs
    update(completed_log_url: nil, completed_log_lines: nil, streaming_log_url: nil)

    # We officially support and "unlimited" number of check steps per job. Split into small groups to avoid large queries and DB load just in-case we have a large number of check steps
    steps.pluck(:id).in_groups_of(50, false) do |ids|
      CheckStep.where(repository_id: repository_id, id: ids).update_all(completed_log_url: nil, completed_log_lines: nil)
    end
  end

  AUTO_MERGE_PR_LIMIT = 100
  def call_auto_merge_job_enqueuer
    return unless check_suite
    return unless successful?

    with_flagged_ar_role do
      GitHub.tracer.in_span("check_run/call_auto_merge_job_enqueuer/enqueue_auto_merge_jobs", kind: :internal) do |_span|
        T.must(repository).pull_requests.open_pulls.not_spammy.where(head_sha: T.must(check_suite).head_sha).limit(AUTO_MERGE_PR_LIMIT).each do |pull|
          GitHub.tracer.in_span("check_run/call_auto_merge_job_enqueuer/enqueue_auto_merge_job_if_enabled", kind: :internal) do |_span|
            pull.enqueue_auto_merge_job_if_enabled
          end
        end
      end
    end
  end

  # to reduce mysql1 queries for: https://github.com/github/c2c-actions-checks/issues/1330
  # will check ff and force ar reading role if enabled
  private def with_flagged_ar_role
    if GitHub.flipper[:checks_enqueue_auto_merge_with_read].enabled?
      ActiveRecord::Base.connected_to(role: :reading) { yield }
    else
      yield
    end
  end

  def create_deployment(environment, is_cloned: false)
    return if deployment.present?
    return if is_cloned

    check_suite = T.must(self.check_suite)

    options = {
      sha: check_suite.head_sha,
      creator: check_suite.creator,
      repository: check_suite.repository,
      environment: environment,
      check_run: self,
      ref: check_suite.head_branch || check_suite.head_sha
    }

    if can_add_deployment_performer?
      # If a dynamic Pages run, mark Pages as the performer
      if check_suite.workflow_run&.workflow&.dynamic_pages_workflow? && GitHub.pages_github_app&.id
        options[:performed_by_integration_id] = GitHub.pages_github_app.id
      else
        # Default to marking Actions as the performer
        options[:performed_by_integration_id] = check_suite.github_app_id
      end
    end

    Deployment.create!(options)
  end

  CHECK_RUN_STATUS_TO_DEPLOYMENT_STATE = {
      # check run statuses
      requested: "pending",
      waiting: "waiting",
      queued: "queued",
      in_progress: "in_progress",
      # check run conclusions
      neutral: "inactive",
      success: "success",
      failure: "failure",
      cancelled: "error",
      action_required: "error",
      timed_out: "error",
      skipped: "inactive",
      stale: "inactive",
  }

  def create_deployment_status(environment_url)
    deployment = self.deployment
    if deployment.present?
      status_state = CHECK_RUN_STATUS_TO_DEPLOYMENT_STATE[(conclusion || status).to_sym]

      if deployment.latest_status && deployment.latest_state == status_state
        # update environment_url
        latest_status = T.must(deployment.latest_status)
        latest_status.update({ environment_url: environment_url }) if latest_status.environment_url != environment_url
      else
        options = { deployment: deployment, creator: deployment.creator, state: status_state, environment_id: deployment.environment_id }
        options[:environment_url] = environment_url if environment_url.present?
        options[:log_url] = details_url
        DeploymentStatus.create!(options)

        unless GitHub.flipper[:actions_environments_block_auto_inactive].enabled?
          # For deployments created from check runs, we always want to mark previous deployments as inactive. We want to
          # include even deployments marked as production, so pass true for `include_production`
          CreateAutoInactiveDeploymentStatuses.perform_later(deployment, true, environment_url)
        end
      end
    else
      errors.add(:deployment, "Deployment should exist, before creating status")
    end
  end

  def update_status_and_deployment_from_gates
    # if all the gates are open, the run should be in a "queued" state since nothing is blocking
    update(status: self.all_gates_open? ? :queued : :waiting)
    create_deployment_status(nil)
  end

  def all_gates_open?
    gate_requests.all?(&:open?)
  end

  def blocked_by_gate?
    gate_requests.any? { |gate_request| gate_request.closed? }
  end

  def manual_approval_gate_request
    gate_requests.find { |gate_request| gate_request.gate&.manual_approval? }
  end

  def custom_gate_requests
    gate_requests.find_all { |gate_request| gate_request.gate&.custom? && gate_request.closed? }
  end

  def wait_gate_request
    gate_requests.find { |gate_request| gate_request.gate&.timeout? }
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
    GitHub.dogstats.increment("actions.check_run.get_signed_completed_log_url.error", tags: ["error:#{T.must(e.class.name).underscore}", "is_results:#{is_results}"])
    Failbot.report(e)
    nil
  end

  # Request log backscrolls for a step from the results service:
  def get_log_scrollback_from_results(step_external_id)
    return nil unless streaming_logs_via_results?

    res = ActionsResults::Twirp.log_client.get_step_log_scrollback(
      workflow_run_backend_id: T.must(check_suite&.external_id),
      workflow_job_run_backend_id: T.must(external_id),
      workflow_step_backend_id: step_external_id,
    )

    return nil unless res.call_succeeded?

    res.value
  end

  # retrieve the signed completed job log URL from actions service through Launch
  def request_completed_log_url_from_actions_service(unauthenticated_url)
    check_suite = T.must(self.check_suite)
    Launch::Twirp::artifacts_exchange_client_for_check_suite(check_suite)
      .exchange_url_for(
        unauthenticated_url:,
        repository: T.must(check_suite.repository),
        resource_type: Launch::Twirp::ResourceType::COMPLETED_JOB_LOG
      )
  end

  # retrieve the signed streaming log URL from actions service through Launch
  def request_streaming_log_url_from_actions_service
    check_suite = T.must(self.check_suite)
    Launch::Twirp::artifacts_exchange_client_for_check_suite(check_suite)
      .exchange_url_for(
        unauthenticated_url: streaming_log_url,
        repository: T.must(check_suite.repository),
        resource_type: Launch::Twirp::ResourceType::STREAMING_LOG
      )
  end

  # retrieve steps from either RAC or the results service
  def get_steps(number = nil)
    return rac_steps(number) unless is_actions_check_run? && workflow_job_run
    return rac_steps(number) if opt_out_from_results?
    return rac_steps(number) unless created_at&.year >= 2024
    science "check_run.get_steps" do |e|
      e.use { rac_steps(number) }
      e.try { results_steps(number) }
      e.compare do |control, candidate|
        control.map(&:name) == candidate.map(&:name) &&
        control.map(&:status) == candidate.map(&:status) &&
        control.map(&:conclusion) == candidate.map(&:conclusion) &&
        control.map(&:external_id) == candidate.map(&:external_id) &&
        non_empty_time(control) == non_empty_time(candidate) &&
        non_empty_log_urls(control) == non_empty_log_urls(candidate)
      end
      e.clean do |value|
        steps_to_hash(value)
      end
    end
  end

  private

  # Normalizes nils and empty strings to nil for scientist comparison and counts the non-empty log urls
  def non_empty_log_urls(steps)
    steps.map { |step| normalize_log_url(step.completed_log_url) }.compact.count
  end

  # Normalizes nils and empty strings to nil for scientist comparison
  def normalize_log_url(log_url)
    log_url.blank? ? nil : log_url
  end

  # Normalizes nils to nil for scientist comparison and rounds time to the nearest second and counts the non-empty times
  def non_empty_time(steps)
    steps.map { |step| normalize_time(step.started_at) }.compact.count +
    steps.map { |step| normalize_time(step.completed_at) }.compact.count
  end

  def normalize_time(time)
    time.blank? ? nil : time
  end

  def rac_steps(number = nil)
    if number.nil?
      steps
    else
      steps.where(number: number)
    end
  end

  def results_steps(number = nil)
    results_steps = steps_from_results
    if number.nil?
      results_steps
    else
      results_steps.select { |step| step.number == number }
    end
  end

  def steps_to_hash(steps)
    hash_steps = steps.map do |step|
      {
        name:         step.name,
        status:       step.status,
        conclusion:   step.conclusion,
        number:       step.number,
        started_at:   step.started_at,
        completed_at: step.completed_at,
        external_id:  step.external_id,
        completed_log_url: step.completed_log_url,
      }
    end

    hash_steps.sort_by { |s| s[:number] }
  end

  # Internal: Do the actual WebSocket notification
  def notify_socket_subscribers
    return unless self.check_suite.present?

    has_steps = ActiveRecord::Base.connected_to(role: :reading) do
      steps.any?
    end

    data = if new_record?
      {
        id: global_relay_id,
        timestamp: created_at,
        duration: duration,
        reason: "check_run ##{id} created: #{status}",
        wait: default_live_updates_wait,
        status: status,
        conclusion: conclusion,
        has_steps: has_steps,
        raw_logs: completed_log_url.present?,
        streaming_logs: streaming_log_url.present?,
      }
    else
      {
        id: global_relay_id,
        timestamp: updated_at,
        duration: duration,
        reason: "check_run ##{id} updated: #{status}",
        wait: default_live_updates_wait,
        status: status,
        conclusion: conclusion,
        has_steps: has_steps,
        raw_logs: completed_log_url.present?,
        streaming_logs: streaming_log_url.present?,
      }
    end

    check_suite = T.must(self.check_suite)

    repository = ActiveRecord::Base.connected_to(role: :reading) do
      GitHub::PrefillAssociations.prefill_associations([check_suite.repository], [:internal_repository, :network])
      check_suite.repository
    end

    # Only notify commit channel if non-hidden actions check suite. Will always notify for non-actions suite
    unless check_suite.hidden && check_suite.workflow_file_path.present?
      GitHub::WebSocket.notify_repository_channel(repository, commit_channel, data)
    end

    GitHub::WebSocket.notify_repository_channel(repository, channel, data)

    GitHub::WebSocket.notify_repository_channel(repository, T.must(workflow_job_run).channel, data) if workflow_job_run

    if status_previously_changed? || conclusion_previously_changed?
      if GitHub.flipper[:pull_request_sub_triggers].enabled?(repository)
        commit = check_suite.commit
        return if commit.nil?
        Platform::Schema.subscriptions.trigger(:commit_checks_updated, { id: commit.global_relay_id })

        if GitHub.flipper[:pull_request_single_subscription].enabled?(repository)
          NotifyPullRequestCommitChecksUpdatedJob.perform_later(repository.id, check_suite.head_sha)
        end
      end
    end
  end

  def images_format_and_size_is_valid
    if images.any? { |image| image[:image_url].blank? }
      errors.add(:images, "must all have image URLs provided")
    end

    # Validate JSON and not YAML as the user provides us with JSON in the API
    if images.to_json.bytesize > IMAGES_BYTESIZE_LIMIT
      errors.add(:images, "array was larger than #{IMAGES_BYTESIZE_LIMIT} bytes")
    end
  end

  def matches_check_suite_repository
    check_suite = self.check_suite
    if check_suite && repository_id && repository_id != check_suite.repository_id
      errors.add(:repository, "does not match the check suite's repository")
    end
  end

  def details_url_is_valid
    return unless self[:details_url]

    parsed_url = URI.parse(self[:details_url])

    unless %w[http https].include?(parsed_url.scheme)
      errors.add(:details_url, "must use the http or https scheme")
    end
  rescue URI::InvalidURIError
    errors.add(:details_url, "is not a valid URL")
  end

  def completed_at_not_in_future
    current_time = T.unsafe(Time.now.utc)
    completed_at = self.completed_at

    if completed_at && completed_at > current_time
      self.completed_at = current_time
    end
  end

  def log_object
    {
      "gh.check_run.id" => id,
      "gh.check_run.status" => status,
      "gh.check_run.conclusion" => conclusion,
      "gh.check_run.created_at" => created_at,
      "gh.check_run.updated_at" => updated_at,
      "gh.check_run.started_at" => started_at,
    }
  end

  def update_suite_rollups
    return unless self.check_suite.present?

    pair_id = SecureRandom.uuid
    log_update_suite_rollups("start", { pair_id: pair_id })

    T.must(check_suite).set_rollup_values!

    log_update_suite_rollups("end", { pair_id: pair_id })
  end

  def size_of_summary
    if (size = summary&.bytesize).present? && size > SUMMARY_BYTESIZE_LIMIT
      errors.add(:summary, "exceeds a maximum bytesize of #{SUMMARY_BYTESIZE_LIMIT}")
    end
  end

  def assign_completed_at
    self.completed_at ||= T.unsafe(Time.now.utc)
  end

  def set_status_completed
    self.status = "completed"
  end

  def set_started_at
    self.started_at ||= T.unsafe(Time.now.utc)
  end

  def delete_previous_check_runs
    check_suite = T.must(self.check_suite)
    repo_id = T.must(check_suite.repository).id
    count = ActiveRecord::Base.connected_to(role: :reading) do
      check_suite.check_runs.where(name: name, repository_id: repo_id).count
    end
    return if count <= MAX_CHECK_RUNS_PER_NAME

    # We limit the number of check runs to query to avoid creating too many jobs
    old_check_run_ids = check_suite.check_runs.where(name: name, repository_id: repo_id).order(id: :asc).limit(100).pluck(:id)
    old_check_run_ids -= [id] # Never delete the current check run.
    DeleteOldCheckRuns.perform_later(old_check_run_ids, repository_id: repo_id)
  end

  def create_workflow_job_run
    check_suite = self.check_suite
    return unless check_suite && check_suite.actions_app? && check_suite.workflow_run

    suite_workflow_run = T.must(check_suite.workflow_run)
    execution = ActiveRecord::Base.connected_to(role: :reading) do
      suite_workflow_run.latest_workflow_run_execution
    end
    original_workflow_run_execution = execution

    if is_cloned_from_previous_run
      # Get the latest (last by id) workflow run execution with the same job_key
      # Forcing index because on some occasions the query planner chooses the wrong index resulting in slow or killed queries, see https://github.com/github/mysql-database-usage/issues/1841
      previous_workflow_job_run = Actions::WorkflowJobRun
        .from("workflow_job_runs FORCE INDEX(idx_repo_id_workflow_run_id_workflow_run_execution_id_job_key)")
        .where(repository_id: check_suite.repository_id, workflow_run_id: suite_workflow_run.id, job_key: job_key)
        .last

      original_workflow_run_execution = previous_workflow_job_run.original_workflow_run_execution if previous_workflow_job_run && previous_workflow_job_run.original_workflow_run_execution
    end

    Actions::WorkflowJobRun.create(
        check_run: self,
        workflow_run: check_suite.workflow_run,
        repository: check_suite.repository,
        job_key: job_key,
        parent_job_id: parent_job_id,
        label_data: labels,
        runner_id: runner_id,
        runner_name: runner_name,
        runner_group_id: runner_group_id,
        runner_group_name: runner_group_name,
        concurrency: concurrency,
        workflow_run_execution: execution,
        original_workflow_run_execution: original_workflow_run_execution,
        summary_url: summary_url,
    )
  end

  def status_changed_to_waiting?
    saved_change_to_status? && status.to_sym == :waiting
  end

  def truncate_fields
    truncate_field(:name, MAX_VARBINARY_FIELD_LENGTH)
    truncate_field(:title, MAX_VARBINARY_FIELD_LENGTH)
    truncate_field(:display_name, MAX_VARBINARY_FIELD_LENGTH)

    external_id = self.external_id
    if external_id.present? && external_id.length > 255
      self.external_id = external_id[0...255]
    end
  end

  def can_add_deployment_performer?
    check_suite = T.must(self.check_suite)
    # Does this Check Suite belong to an Actions workflow run?
    check_suite.actions_app? && GitHub.actions_enabled? &&
      # Is the actor a real user (i.e. not a bot/org)?
      # We don't want any GitHub Apps to be shown as acting on behalf of other GitHub Apps/non-users... even if they
      # actually are doing exactly that underneath. ;)
      check_suite.creator&.user?
  end

  # Request completed job log from the results service:
  # 1. Parse the results:// URI to obtain the workflow run ID and workflow job run ID
  # 2. Make a Twirp request to results-core to retrieve the completed step log URL
  # 3. If the Twirp call made in (2) is successful return the log URL
  # 4. If the Twirp call made in (2) fails, fallback to the actions service URL in the query params
  def get_completed_log_url_from_results(url)
    return nil unless url

    matches = ActionsResults::Utils.get_ids_from_results_url(url)
    return nil unless matches

    res = ActionsResults::Twirp.log_client.get_completed_job_log_url(
      workflow_job_run_backend_id: T.must(matches[:workflow_job_run_backend_id]),
      workflow_run_backend_id: T.must(matches[:workflow_run_backend_id]),
    )

    if !res.call_succeeded? || !res.value.log_url.present?
      GitHub.dogstats.increment("actions.workflow_job_run.get_completed_log_url_from_results.fallback_to_actions_service", tags: ["status_code:#{res.status}"])
      # fallback to the actions service to retrieve logs
      return fallback_to_actions_service(url)
    end

    res.value.log_url
  end

  # If we cannot find the logs in the Results Service we are going to fallback to the actions service. The URL for
  # logs in the actions service is in the query params of the results:// URL. The query param is called actions_url.
  # For more information see https://github.com/github/actions-results/pull/467
  def fallback_to_actions_service(url)
    actions_service_url = ActionsResults::Utils.actions_url(url)

    return nil if actions_service_url.nil?

    get_completed_log_url_from_actions_service(actions_service_url)
  end

  # This performs the request to retrieve the signed
  # completed job log URL from actions service through Launch
  def get_completed_log_url_from_actions_service(url)
    return nil if url.blank?

    result = request_completed_log_url_from_actions_service(url)

    if result.call_succeeded?
      GitHub.dogstats.increment("actions.exchange_url_request.succeeded", tags: ["check_logs"])

      result.value.authenticated_url
    else
      GitHub.dogstats.increment("actions.exchange_url_request.failed", tags: ["check_logs"])

      nil
    end
  end

  def normalize_name
    # Strip leading and trailing whitespace from name only.
    # Whitespace has only been an issue with the Checks API which doesn't expose display_name.
    name.strip! if name.present?
  end
end
