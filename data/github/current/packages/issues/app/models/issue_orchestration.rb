# typed: true
# frozen_string_literal: true

class IssueOrchestration < ApplicationRecord::Domain::IssuesPullRequests
  include Orchestration
  include RepositoryOrchestrationBase

  # Aligned with the 10K frontend limit (COPILOT_INSTRUCTIONS_MAX_LENGTH in
  # CopilotAssignmentForm.tsx). The issue_orchestrations.data column is TEXT
  # (max 65,535 bytes) and the copilot_context is YAML-serialized into it.
  # 10K of typical text serializes to ~10KB YAML, well within budget.
  CUSTOM_INSTRUCTIONS_MAX_LENGTH = 10_000

  CopilotContext = T.type_alias do
    T.nilable(
      T.any(
        { request_token: String, attributes: Issues::AgentAssignmentNewAttributes, user_session_id: T.nilable(Integer) },
        { request_token: String, attributes: Issues::AgentAssignmentNewAttributes }
      )
    )
  end

  DANGLING_ORCHESTRATIONS_TIME_INTERVAL_MAX_AGO_TIME = 1.minute.freeze
  DANGLING_ORCHESTRATIONS_TIME_INTERVAL_MIN_AGO_TIME = 15.seconds.freeze

  DANGLING_ORCHESTRATIONS_STEPS = %w[set_assignees job_start]

  belongs_to :issue
  validates :issue_id, presence: true, unless: :skip_issue_id_validation

  protected def target_uniqueness_condition_on_start; end

  class << self
    private

    attr_writer :feature_flag_names
  end

  def initialize(_attributes)
    super

    # persist feature flags in the orchestration so they are consistent across all steps
    self.data[:feature_flags] ||= {}
    self.data[:feature_flags].merge!(feature_flags)
  end

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

  def modifying_integration
    return Integration.find(data[:modifying_integration_id]) if data[:modifying_integration_id]

    nil
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
      "gh.issue.orchestration.uses_domain" => uses_domain?,
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

  def datadog_tags
    ["uses_domain:#{uses_domain?}"]
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

      GitHub.dogstats.increment("#{base_orchestration_name}.dangling_start", tags: ["type:#{orchestration.type}", "step:#{orchestration.step_name}"])

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

  sig { params(issue: Issue, actor: T.nilable(User), uses_domain: T::Boolean, is_duplicated: T::Boolean, copilot_context: CopilotContext).returns(CreateIssueOrchestration) }
  def self.create_issue!(issue:, actor:, uses_domain: false, is_duplicated: false, copilot_context: nil)
    data = ActiveRecord::Base.connected_to(role: :reading) do
      {
        actor_id: actor&.id,
        body_template_name: issue.body_template_name,
        importing: issue.importing?,
        uses_domain: uses_domain,
        modifying_integration_id: issue.modifying_integration&.id,
        reconcile_checklist: issue.has_checklist_items?,
        options: { # only added for logging purposes:
          skip_create_issue_orchestration: issue.skip_create_issue_orchestration,
          skip_update_issue_orchestration: issue.skip_update_issue_orchestration,
        },
        is_duplicated: is_duplicated,
        copilot_context: serialize_copilot_context(copilot_context),
      }.compact_blank
    end

    create_attrs = {
      issue: issue,
      data: data,
    }
    create_attrs[:repository_id] = issue.repository_id
    CreateIssueOrchestration.create!(**create_attrs)
  end

  def self.update_issue!(issue:, actor:, uses_domain: false, copilot_context: nil)
    serialized_copilot_context = serialize_copilot_context(copilot_context)

    data = {
      actor_id: actor&.id,
      importing: issue.importing?,
      uses_domain: uses_domain,
      modifying_integration_id: issue.modifying_integration&.id,
      reconcile_checklist: issue.has_checklist_items?,
      needs_community_profile_update:
        issue.should_update_repo_community_profile ||
        (issue.saved_change_to_state? && issue.should_update_repo_community_profile(issue.labels.to_a)),
      copilot_context: serialized_copilot_context,
      options: { # only added for logging purposes:
        skip_create_issue_orchestration: issue.skip_create_issue_orchestration,
        skip_update_issue_orchestration: issue.skip_update_issue_orchestration,
      }
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
        second_to_last_edit = IssueEdit.select(:id).where(issue_id: issue.id, repository_id: issue.repository_id).second_to_last
        data[:title_or_body_changes].merge!(issue_edit_id: second_to_last_edit.id) if second_to_last_edit
      end
    end

    if !issue.skip_hydro_update_event_instrumentation && issue.orchestrate_hydro_update_event_instrumentation
      data[:instrument_hydro_update_event_enabled] = true
    end

    data[:is_converting_to_pr] = issue.saved_change_to_pull_request_id?(from: nil)

    update_attrs = {
      issue: issue,
      data: data.compact_blank,
    }
    update_attrs[:repository_id] = issue.repository_id
    UpdateIssueOrchestration.create!(**update_attrs)
  end

  def self.delete_issue(issue:, actor:)
    data = {
      actor_id: actor&.id,
      modifying_integration_id: issue.modifying_integration&.id,
    }.compact_blank

    delete_attrs = {
      issue: issue,
      data: data,
    }
    delete_attrs[:repository_id] = issue.repository_id
    DeleteIssueOrchestration.create(**delete_attrs)
  end

  sig { returns(T.nilable(User)) }
  def actor
    return nil if data[:actor_id].blank?

    @actor ||= ActiveRecord::Base.connected_to(role: :reading) { User.find_by(id: data[:actor_id]) }
  end

  sig { returns(T::Boolean) }
  def uses_domain?
    !!data[:uses_domain]
  end

  def self.initiated_by
    GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"
  end

  sig { returns(T::Boolean) }
  def should_update_close_issue_references
    T.must(issue).pull_request? && !importing?
  end

  sig { params(feature_name: Symbol).returns(T::Boolean) }
  def feature_enabled?(feature_name)
    return false unless data[:feature_flags]

    !!data[:feature_flags][feature_name]
  end

  # feature flags are persisted in the orchestration data
  # for consistency during execution across all steps
  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def feature_flags
    return {} if self.class.feature_flag_names.blank?

    ::FeatureFlag.vexi.preload(self.class.feature_flag_names, instrumentation_properties: {
      "code.namespace": self.class.name&.underscore,
    }) if GitHub.enterprise? && actor

    self.class.feature_flag_names.map do |feature_flag_name|
      [feature_flag_name, actor&.feature_flag_enabled_or_raise?(feature_flag_name) || false] # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end.to_h.compact
  end

  sig { returns(T::Array[Symbol]) }
  def self.feature_flag_names
    @feature_flag_names || []
  end

  sig { returns(T.nilable(Issue)) }
  def issue_with_modifying_integration
    issue&.modifying_integration = modifying_integration

    issue
  end

  private

  sig { returns(T::Boolean) }
  def reconcile_checklist?
    !!data[:reconcile_checklist]
  end

  sig { returns(T::Boolean) }
  def needs_community_profile_update?
    !!data[:needs_community_profile_update]
  end

  # feature flags defined in this list will be persisted in the orchestration data
  # we need to do it for consistency across all steps as well for efficient preloading
  sig { params(feature_flag_names: Symbol).void }
  def self.persist_feature_flags(*feature_flag_names)
    @feature_flag_names = feature_flag_names
  end
  private_class_method :persist_feature_flags

  sig { params(context: CopilotContext).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.serialize_copilot_context(context)
    return nil if context.nil?

    # Serialize the AgentAssignmentNewAttributes struct to a hash
    serialized = context.dup
    if serialized[:attributes].is_a?(Issues::AgentAssignmentNewAttributes)
      attributes_hash = serialized[:attributes].serialize
      # Convert Repository object to ID for storage
      if attributes_hash["target_repository"].is_a?(Repository)
        attributes_hash["target_repository_id"] = attributes_hash["target_repository"].id
        attributes_hash.delete("target_repository")
      end
      # Truncate custom_instructions to prevent TEXT column overflow (issue_orchestrations.data)
      if attributes_hash["custom_instructions"].is_a?(String) &&
          attributes_hash["custom_instructions"].length > CUSTOM_INSTRUCTIONS_MAX_LENGTH
        attributes_hash["custom_instructions"] = attributes_hash["custom_instructions"]
          .truncate(CUSTOM_INSTRUCTIONS_MAX_LENGTH, omission: "... [truncated]")
      end
      serialized[:attributes] = attributes_hash
    end
    serialized
  end
  private_class_method :serialize_copilot_context

  sig { params(serialized: T.nilable(T::Hash[Symbol, T.untyped])).returns(CopilotContext) }
  def self.deserialize_copilot_context(serialized)
    return nil if serialized.nil?

    if serialized[:attributes].nil?
      GitHub.logger.warn("Copilot context deserialization skipped: attributes is nil")
      return nil
    end

    # Current format requires request_token - legacy formats without it are no longer supported
    if serialized[:request_token].blank?
      GitHub.logger.warn("Copilot context deserialization skipped: request_token missing (legacy format no longer supported)")
      return nil
    end

    # Deserialize the attributes hash back to AgentAssignmentNewAttributes, extracting only relevant keys
    deserialized = {
      request_token: serialized[:request_token],
      attributes: serialized[:attributes],
    }

    # Preserve user_session_id if present (for retry logic)
    if serialized[:user_session_id].present?
      deserialized[:user_session_id] = serialized[:user_session_id]
    end

    if deserialized[:attributes].is_a?(Hash)
      attributes_hash = deserialized[:attributes].dup
      # Convert repository ID back to Repository object
      if attributes_hash["target_repository_id"]
        target_repo = Repositories::Public.get_active_or_deleted(attributes_hash["target_repository_id"])
        unless target_repo
          GitHub.logger.warn("Copilot context deserialization failed: target repository #{attributes_hash["target_repository_id"]} not found")
          return nil
        end
        attributes_hash["target_repository"] = target_repo
        attributes_hash.delete("target_repository_id")
      end
      deserialized[:attributes] = Issues::AgentAssignmentNewAttributes.from_hash(attributes_hash)
    end
    T.cast(deserialized, CopilotContext)
  end
  private_class_method :deserialize_copilot_context

  sig { returns(T::Boolean) }
  def is_duplicated?
    !!data[:is_duplicated]
  end

  sig { returns(CopilotContext) }
  def copilot_context
    self.class.send(:deserialize_copilot_context, data[:copilot_context])
  end

  # Builds agent-specific copilot contexts for multiple agents
  # This is shared logic used by both CreateIssueOrchestration and UpdateIssueOrchestration
  # For CreateIssueOrchestration: triggers for all assigned agents (previous_assignee_ids is nil/empty)
  # For UpdateIssueOrchestration: triggers only for newly assigned agents
  sig do
    params(
      issue: Issue,
      actor: User,
      base_context: T::Hash[Symbol, T.untyped]
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def build_agent_specific_copilot_contexts(issue:, actor:, base_context:)
    assignment_attributes = base_context[:attributes]
    return [] unless assignment_attributes.is_a?(Issues::AgentAssignmentNewAttributes)

    repository = T.must(issue.repository)

    # Calculate which assignee IDs need agent jobs triggered
    # For create: all assignees (previous_assignee_ids is nil/empty)
    # For update: only new assignees (current - previous)
    previous_assignee_ids = Array(data[:previous_assignee_ids]).compact
    current_assignee_ids = issue.assignees.reload.map(&:id).compact
    assignee_ids = if previous_assignee_ids.empty?
      current_assignee_ids
    else
      current_assignee_ids - previous_assignee_ids
    end

    return [] if assignee_ids.empty?

    enabled_agents = AgenticApp.enabled_for_repository(repository, actor)
    agent_entries = enabled_agents.each_with_object({}) do |agent, memo|
      if !agent.assignable? && FeatureFlag.vexi.enabled?(:filter_non_assignable_agent_bots, repository, repository.owner, default: false)
        integration = agent.integration
        bot = integration&.bot
        GitHub.logger.info({
          body: "[Copilot-Assign] Skipping non-assignable agent in build_agent_specific_copilot_contexts",
          agent_class: agent.class.name,
          bot_id: bot&.id,
          repository_id: repository.id,
        })
        GitHub.dogstats.increment("issues.copilot.non_assignable_agent_skipped")
        next
      end
      integration = agent.integration
      bot = integration&.bot
      next unless integration && bot&.id
      memo[bot.id] = integration.id
    end

    assignee_ids.filter_map do |assignee_id|
      integration_id = agent_entries[assignee_id]
      next unless integration_id

      updated_attributes = assignment_attributes.dup
      updated_attributes.agent_id = integration_id

      base_context.dup.tap { |ctx| ctx[:attributes] = updated_attributes }
    end
  end
end
