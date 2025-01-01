# typed: true
# frozen_string_literal: true
class IssueOrchestration < ApplicationRecord::Domain::IssuesPullRequests
  include Orchestration
  include RepositoryOrchestrationBase

  DANGLING_ORCHESTRATIONS_TIME_INTERVAL_MAX_AGO_TIME = 1.minute.freeze
  DANGLING_ORCHESTRATIONS_TIME_INTERVAL_MIN_AGO_TIME = 15.seconds.freeze

  DANGLING_ORCHESTRATIONS_STEPS = %w[set_assignees job_start]

  belongs_to :issue
  validates :issue_id, presence: true, unless: :skip_issue_id_validation

  protected def target_uniqueness_condition_on_start; end

  def self.base_orchestration
    IssueOrchestration
  end

  def self.job_class
    IssueOrchestrationJob
  end

  def self.log_prefix
    "gh.issue"
  end

  def skip_issue_id_validation
    false
  end

  def validate_no_duplicates
    if issue.present?
      existing_id = self.class.active.where(type: self.class, issue_id: T.must(issue_id), repository_id: T.must(repository_id)).pluck(:id).first
      if existing_id.present?
        errors.add(:base, :duplicate, message: "orchestration in progress #{existing_id}")
      end
    end
  end

  def log_data(options = {})
    {
      "code.namespace" => self.class.name,
      "gh.issue.id" => issue_id,
      "gh.issue.orchestration.id" => id,
      "gh.issue.orchestration.type" => type,
      "gh.issue.orchestration.state" => state,
      "gh.issue.orchestration.step_name" => step_name,
      "gh.issue.orchestration.attempts" => attempts,
      "gh.issue.orchestration.data" => data,
      "gh.issue.orchestration.error_message" => error_message,
      "gh.issue.orchestration.initiated_by" => self.class.initiated_by,
      "gh.repo.id" => repository_id,
      "gh.actor.id" => data[:actor_id],
      "gh.request_id" => GitHub.context[:request_id],
    }.merge(options)
  end

  def failbot_data
    {
      "repo_id" => repository_id,
      "gh.issue.id" => issue_id,
      "gh.issue.orchestration.id" => id,
      "gh.issue.orchestration.step_name" => step_name,
      "gh.issue.orchestration.type" => type
    }
  end

  def build_hydro_event_message
    self.class.build_hydro_event_message(repository_id, issue_id)
  end

  def self.dangling_orchestrations_batch(starting_timestamp, offset_id, batch_size)
    # All orchestrations which have been created but not started and not touched
    # in the last 15 seconds can be started manually.
    #
    # Don't pick up older orchestrations, they will be picked up by the sweeper and marked as abandoned.
    # Furthermore, don't start orchestrations which have synchronous steps before starting the job.
    max_ago = starting_timestamp - DANGLING_ORCHESTRATIONS_TIME_INTERVAL_MAX_AGO_TIME
    min_ago = starting_timestamp - DANGLING_ORCHESTRATIONS_TIME_INTERVAL_MIN_AGO_TIME

    time_range_interval = max_ago..min_ago

    IssueOrchestration.throttle do
      IssueOrchestration.
        where(state: [:created, :started], updated_at: time_range_interval, step_name: DANGLING_ORCHESTRATIONS_STEPS).
        where("id > ?", offset_id).
        order(id: :asc).
        limit(batch_size)
    end
  end

  def self.start_dangling_orchestrations(batch)
    GitHub.logger.info(
      "Attempting to start #{batch.size} dangling issue orchestrations",
      {
        "code.namespace": self.name,
        "code.function": __method__
      })

    batch.each do |orchestration|
      orchestration.log_info("Trying to start dangling orchestration")

      GitHub.dogstats.increment("#{base_orchestration_name}.dangling_start", tags: ["type:#{self.name}"])

      valid = orchestration.execute

      orchestration.log_info("Orchestration no longer valid") unless valid
    end
  end

  def self.build_hydro_event_message(repository_id, issue_id)
    message = {
      repository_id: repository_id,
      issue_id: issue_id,
      request_id: GitHub.context[:request_id],
    }
  end

  def self.create_issue!(issue:, actor:)
    data = {
      actor_id: actor&.id,
      body_template_name: issue.body_template_name,
      importing: issue.importing?
    }.compact_blank

    CreateIssueOrchestration.create!(
      repository: issue.repository,
      issue: issue,
      data: data,
    )
  end

  def self.update_issue!(issue:, actor:)
    data = {
      actor_id: actor&.id,
      importing: issue.importing?
    }

    if issue.title_or_body_changed?
      data[:title_or_body_changes] = {}

      old_title, current_title = issue.previous_changes[:title]
      if old_title != current_title
        data[:title_or_body_changes].merge!(old_title: old_title, current_title: current_title)
      end

      if issue.body_previously_was != issue.body
        # The last edit contains the current body of the issue
        # We want to fetch the second-to-last edit to get the previous body
        second_to_last_edit = IssueEdit.select(:id).where(issue_id: issue.id).second_to_last
        data[:title_or_body_changes].merge!(issue_edit_id: second_to_last_edit.id) if second_to_last_edit
      end
    end

    if !issue.skip_hydro_update_event_instrumentation && issue.orchestrate_hydro_update_event_instrumentation
      data[:instrument_hydro_update_event_enabled] = true
    end

    UpdateIssueOrchestration.create!(
      repository: issue.repository,
      issue: issue,
      data: data.compact_blank,
    )
  end

  def self.delete_issue(issue:, actor:)
    data = {
      actor_id: actor&.id,
    }.compact_blank

    DeleteIssueOrchestration.create(
      issue: issue,
      repository: issue.repository,
      data: data,
    )
  end

  sig { returns(T.nilable(User)) }
  def actor
    return nil if data[:actor_id].blank?
    @actor ||= User.find_by(id: data[:actor_id])
  end

  def self.initiated_by
    GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"
  end

  sig { returns(T::Boolean) }
  def should_update_close_issue_references
    T.must(issue).pull_request? && !importing?
  end
end
