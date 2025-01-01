# typed: false
# frozen_string_literal: true
require "github-launch"

class Artifact < ApplicationRecord::Domain::RepositoriesActionsChecks
  include Instrumentation::Model
  include GitHub::Tracing

  belongs_to :repository
  belongs_to :check_suite, inverse_of: :artifacts
  belongs_to :workflow_run, class_name: "Actions::WorkflowRun", inverse_of: :artifacts

  attribute :name, StringFromBinary.new
  attribute :skip_file_deletion, :boolean

  validates :source_url, presence: true
  validates :name, presence: true
  validates :size, presence: true

  validate :matches_check_suite_repository

  after_commit :notify_socket_subscribers, on: [:create, :update]
  after_commit :emit_artifact_add_event, on: [:create]
  after_commit :instrument_destruction, on: :destroy

  before_destroy -> { delete_from_file_storage(raise_on_error: false) }
  before_destroy :emit_artifact_remove_event

  trace_method :notify_socket_subscribers
  trace_method :emit_artifact_add_event

  MAX_READ_LIMIT = 1_000
  # results://actions-results/run/<workflow run ID>/job/<workflow job run ID>/artifact/<artifact name>
  ACTIONS_RESULTS_URI_REGEX = /results:\/\/actions-results\/run\/(?<workflow_run_backend_id>[A-Fa-f\d-]+)\/job\/(?<workflow_job_run_backend_id>[A-Fa-f\d-]+)\/artifact\/*/i

  def expired?
    if expires_at
      expires_at < Time.now
    else
      created_at + 90.days < Time.now
    end
  end

  def not_expired?
    !expired?
  end

  def self.delete_artifacts_from_actions_service(check_suite:, artifact_name: "", raise_on_error: true)
    return unless check_suite.present?

    repository_global_relay_id = Repository::ActionsDependency.global_relay_id(check_suite.repository_id)

    result = Launch::Twirp::artifacts_exchange_client_for_check_suite(check_suite).delete_artifact(
      repository_global_id: repository_global_relay_id,
      execution_id: check_suite.external_id,
      artifact_name: artifact_name,
    )

    if raise_on_error && !result.call_succeeded?
      raise "Could not delete the artifact from file storage"
    end
  end

  def transfer(old_owner:, new_owner:)
    # No need to do anything if the artifact has already expired
    return if expired?

    emit_artifact_event("remove", owner: old_owner)
    emit_artifact_event("add", owner: new_owner)
  end

  # This lets Billing know the artifact has expired. So we can stop billing the customer for it.
  def emit_artifact_expired_event
    emit_artifact_event("expired")
  end

  def get_results_ids_from_source_url
    return nil unless source_url && ActionsResults::Utils.is_results_url?(source_url)

    matches = source_url.match(ACTIONS_RESULTS_URI_REGEX)

    return nil unless matches

    {
      workflow_job_run_backend_id: matches[:workflow_job_run_backend_id],
      workflow_run_backend_id: matches[:workflow_run_backend_id],
    }
  end

  def workflow_run_backend_id
    get_results_ids_from_source_url.fetch(:workflow_run_backend_id, nil)
  end

  def workflow_job_run_backend_id
    get_results_ids_from_source_url.fetch(:workflow_job_run_backend_id, nil)
  end

  def is_results_artifact?
    ActionsResults::Utils.is_results_url?(source_url)
  end

  private

  def matches_check_suite_repository
    if check_suite && repository_id && repository_id != check_suite.repository_id
      errors.add(:repository, "does not match the check suite's repository")
    end
  end

  def delete_from_file_storage(raise_on_error: true)
    return if skip_file_deletion

    if is_results_artifact?
      key = "actions.actions_results_artifact_delete"
      results_ids = get_results_ids_from_source_url
      raise "unable to fetch result IDs from results artifact source url" unless results_ids

      result = ActionsResults::Twirp.artifact_client.delete_artifact(
        workflow_job_run_backend_id: results_ids[:workflow_job_run_backend_id],
        workflow_run_backend_id: results_ids[:workflow_run_backend_id],
        name: name,
      )

      if result.call_succeeded? && result.value&.ok
        GitHub.dogstats.increment("#{key}.succeeded")
      else
        GitHub.dogstats.increment("#{key}.failed")
        raise "Failed to delete artifact from file storage" if raise_on_error
      end
    else
      Artifact.delete_artifacts_from_actions_service(check_suite: check_suite, artifact_name: name, raise_on_error: raise_on_error)
    end
  end

  def notify_socket_subscribers
    return if check_suite.workflow_run.nil?
    data = {
      timestamp: updated_at,
      wait: default_live_updates_wait,
      reason: "artifact created or updated",
    }

    ActiveRecord::Base.connected_to(role: :reading) do
      GitHub::WebSocket.notify_repository_channel(self.repository, check_suite.workflow_run.artifacts_channel, data)

      # The views/checks/_artifacts.html.erb partial through its parent still relies on the main check suite channel
      GitHub::WebSocket.notify_repository_channel(self.repository, check_suite.channel, data)
    end
  end

  # This lets Billing know the artifact has been removed. So we can stop billing the customer for it.
  def emit_artifact_remove_event
    emit_artifact_event("remove")
  end

  # This lets Billing know the artifact has been created. So we can start billing the customer for it.
  def emit_artifact_add_event
    emit_artifact_event("add")
  end

  def emit_artifact_event(event_type, owner: nil)
    repo = ActiveRecord::Base.connected_to(role: :reading) { Repository.find_by(id: self.repository_id) }

    visibility = (repo.public? ? "public" : "private") if repo
    owner_id = owner&.id || repo&.owner_id

    message = {
      artifact_id: self.id,
      artifact_global_id: self.to_global_id.to_s,
      artifact_name: self.name,
      artifact_repository_owner_id: owner_id,
      artifact_repository_id: self.repository_id,
      artifact_repository_visibility: visibility,
      artifact_size_in_bytes: self.size,
      check_suite_id: self.check_suite_id,
      created_at: self.created_at,
      event_type: event_type,
    }

    if event_type == "add" || event_type == "expired"
      message[:expires_at] = self.expires_at
    else
      message[:previously_expired_at] = self.expires_at
    end

    GlobalInstrumenter.instrument("actions.artifact_storage_event", message)
  end

  def instrument_destruction
    # Ignore when the artifact is destroyed because the repository was deleted. It'd be too noisy
    return if check_suite.nil?

    actor = User.find_by(id: GitHub.context[:actor_id])
    instrument :destroy, actor: actor, repo: check_suite.repository, artifact: self
  end
end
