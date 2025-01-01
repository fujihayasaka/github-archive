# typed: false
# frozen_string_literal: true
require "scientist"

class Actions::Workflow < ApplicationRecord::Domain::RepositoriesActionsChecks
  class CannotBeEnabledError < StandardError; end
  class CannotBeDisabledError < StandardError; end
  class NotActiveError < StandardError; end
  class AlreadyPinnedError < StandardError; end
  class MaxPinnedWorkflowsReachedError < StandardError; end
  class AlreadyUnpinnedError < StandardError; end
  class CannotPinInactiveWorkflowError < StandardError; end
  class UserCannotPinWorkflowError < StandardError; end

  self.table_name = "workflows"

  extend GitHub::Encoding
  force_utf8_encoding :name, :path

  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model

  belongs_to :repository
  destroy_in_background_with :repository, sharding_key: :repository_id, sharding_value_key: :id

  has_many :workflow_runs, inverse_of: :workflow
  destroy_dependents_in_background :workflow_runs, sharding_key: :repository_id, sharding_value_key: :repository_id
  has_one :pinned_workflow, -> (workflow) { where(repository_id: workflow.repository_id) }, inverse_of: :workflow, dependent: :destroy

  enum :state, { active: 0, deleted: 1, disabled_fork: 2, disabled_inactivity: 3, disabled_manually: 4 }

  after_create :create_sequence
  before_save :update_timestamps, if: :state_changed?
  before_save :unpin_inactive, if: :state_changed?

  scope :most_recent, -> { order(id: :desc) }
  scope :active, -> { where(state: "active") }
  scope :not_deleted, -> { where.not(state: "deleted") }
  scope :lab, -> { where("path LIKE ?", "#{WORKFLOWS_LAB_PATH}%") }
  scope :prod, -> { where("path LIKE ?", "#{WORKFLOWS_PATH}%") }
  scope :with_valid_path, -> { where.not(path: "").where.not(path: "Build Failed") }
  scope :required, -> { where.not(imposer_repository_id: 0) }
  scope :non_required, -> { where(imposer_repository_id: 0) }

  # Public: Find workflows that are suitable for presentation to anon and non-spammy users
  #
  # Returns a scope.
  scope :viewable_workflows, -> {
    where(<<-SQL)
      (present_in_default_branch = 1 OR EXISTS (
        SELECT 1 FROM workflow_runs
        WHERE workflow_id = workflows.id
          AND repository_id = workflows.repository_id
          AND user_hidden = 0
      ))
    SQL
  }

  # Public: Show spammy users their spammy workflows.
  #
  # Returns a scope.
  scope :spammer_viewable_workflows, lambda { |spammer_id|
    where(<<-SQL, actor_id: spammer_id)
      (present_in_default_branch = 1
        OR EXISTS(
          SELECT 1 FROM workflow_runs
          WHERE workflow_id = workflows.id
            AND repository_id = workflows.repository_id
            AND user_hidden = 0
        ) OR EXISTS(
          SELECT 1 FROM workflow_runs
          WHERE workflow_id = workflows.id
            AND repository_id = workflows.repository_id
            AND actor_id = :actor_id
        )
      )
    SQL
  }

  WORKFLOWS_BASE_PATH = ".github/"
  WORKFLOWS_PATH = "#{WORKFLOWS_BASE_PATH}workflows/"
  WORKFLOWS_LAB_PATH = "#{WORKFLOWS_BASE_PATH}workflows-lab/"
  WORKFLOW_PATHS = [WORKFLOWS_PATH, WORKFLOWS_LAB_PATH]

  # This is how required workflow paths are propagated across Launch and actions
  # services and are also stored in check_suites.
  #
  # Eg: required/1234/required_workflows/test.yml
  REQUIRED_WORKFLOWS_PATH_METADATA_REGEX = /\Arequired\/[0-9]+\/.+[.]{1}y[a]?ml\z/
  REQUIRED_WORKFLOWS_BASE_PATH = "required/"
  REQUIRED_WORKFLOWS_ROUTE_PREFIX = "required"

  DYNAMIC_BASE_PATH = "dynamic/"

  PLACEHOLDER_NAME = "(Unnamed workflow)"

  # Number of days after a scheduled workflow is marked as disabled in a public repo since last activity
  REPOSITORY_INACTIVITY_THRESHOLD = 60
  INACTIVITY_WARNING_WINDOW = 7

  def self.full_path_from_filename(filename)
    filename.start_with?(WORKFLOWS_PATH) ? filename : "#{WORKFLOWS_PATH}#{filename}"
  end

  def self.lab_path_from_filename(filename)
    filename.start_with?(WORKFLOWS_LAB_PATH) ? filename : "#{WORKFLOWS_LAB_PATH}#{filename}"
  end

  def self.dynamic_path_from_filename(filename)
    filename.start_with?(DYNAMIC_BASE_PATH) ? filename : "#{DYNAMIC_BASE_PATH}#{filename}"
  end

  def self.build_dynamic_workflow_path(integration, slug)
    # Rebuilds the workflow path for a dynamic workflow as done in the launch code. See:
    # https://github.com/github/launch/blob/b5a67d611fa2cf4a8640e4be4a986db5b290b72c/flow/flowevents/dynamic.go#L12
    "#{DYNAMIC_BASE_PATH}#{integration}/#{slug}"
  end

  # returns the integration name and slug if the workflow file path is well formed and a dynamic path.
  # file_path = dynamic/pages/pages-build-deployment
  def self.extract_dynamic_workflowfile_path(file_path)
    if file_path&.start_with?(DYNAMIC_BASE_PATH)
      dynamic_path = file_path[DYNAMIC_BASE_PATH.length..-1] # remove the DYNAMIC_BASE_PATH prefix
      components = dynamic_path.split("/")
      [true, components[0], components[1]]
    else
      false
    end
  end

  # Required workflows have a special UI route to avoid conflicts with
  # non required workflows. We have to parse the route and get the
  # information needed to fetch a Workflow entity.
  #
  # Format: required/<workflow_source_repo_nwo>/<workflow_path>.yml
  def self.parse_required_workflow_filename(filename)
    split_file_path = filename.split("/")
    source_repo_nwo = [split_file_path[1], split_file_path[2]].join("/")
    split_file_path.slice!(0..2)

    [split_file_path.join("/"), Repository.nwo(source_repo_nwo)&.id]
  end

  # Allows API to find a workflow via ID or filename.
  def self.find_from_id_or_filename(workflow_id)
    path = Actions::Workflow.full_path_from_filename(workflow_id)
    where(id: workflow_id).or(where(path: path)).first
  end

  # returns the not-deleted workflow for a given filename
  def self.find_from_filename(filename, is_lab: nil)
    imposer_repo_id = 0
    if filename.starts_with?(REQUIRED_WORKFLOWS_BASE_PATH)
      path, imposer_repo_id = parse_required_workflow_filename(filename)
    elsif filename.match?(/\.ya?ml\z/)
      path = is_lab ? lab_path_from_filename(filename) : full_path_from_filename(filename)
    else
      path = dynamic_path_from_filename(filename)
    end

    attrs = { path: path, imposer_repository_id: imposer_repo_id }
    where(attrs).not_deleted.first
  end

  def self.public_and_scheduled?(event, repository)
    event == "schedule" && repository.public
  end

  # Used in badge URL generation as the name can be a path component and newlines cause
  # the routes to not match for *_path and *_url helper methods.
  def self.url_safe_name(name)
    name.gsub("\n", "%0A")
  end

  def self.decode_url_safe_name(encoded)
    encoded.gsub("%0A", "\n")
  end

  def filename
    return path.gsub(DYNAMIC_BASE_PATH, "") if dynamic? # Keep integration/slug

    return path.split("/").last unless required?

    required_workflow_file_name if required?
  end

  def required_workflow_file_name
    source_repo = required_workflow_source_repo
    return if source_repo.nil?

    [REQUIRED_WORKFLOWS_ROUTE_PREFIX, source_repo.nwo, path].join("/")
  end

  # Used for filtering by workflow name.
  # The (Lab) prefix is important to filter by lab/not-lab in the Actions tab
  def visible_name
    lab? ? "#{name} (Lab)" : name
  end

  def url_safe_name
    self.class.url_safe_name(name)
  end

  def lab?
    path.start_with?(WORKFLOWS_LAB_PATH)
  end

  def dynamic_dependabot_workflow?
    dynamic_workflow_integration == "dependabot"
  end

  def dynamic_codespaces_workflow?
    dynamic_workflow_integration == "codespaces"
  end

  def dynamic_codeql_workflow?
    dynamic_workflow_integration == "codeql"
  end

  def dynamic_code_scanning_workflow?
    dynamic_workflow_integration == "github-code-scanning"
  end

  def dynamic_pages_workflow?
    dynamic_workflow_integration == "pages"
  end

  def dynamic_immutable_actions_migration_workflow?
    dynamic_workflow_integration == "immutable-actions-migration"
  end

  def required?
    imposer_repository_id > 0
  end

  def dispatch_inputs(branch_ref: nil)
    repository.async_network.then do
      workflow_dispatch_inputs_with_environment(branch_ref)&.map { |input| { "workflow" => self, "input" => input } }
    end
  end

  # A "parsed workflow" simply parses the .yaml file of the workflow and turns it into a ruby object.
  # An "ENVIRONMENT" input type does not define its' own choices in the .yaml, it pulls them from
  # the repository. So, we do that look up here to properly expose these choices.
  # See `EnvironmentInputComponent` to where this is done in the dotcom UI.
  def workflow_dispatch_inputs_with_environment(branch_ref)
    inputs = Actions::ParsedWorkflow.parse_from_yaml(repository, path, branch_ref)&.workflow_dispatch_inputs
    inputs&.map do |input|
      if input[1][:type] == "environment"
        input[1][:options] = repository.environments.pluck(:name)
      end

      input
    end
  end

  # Actions does not currently have any dynamic workflows
  # Debug workflows were the only case of this, see https://github.com/github/c2c-actions-experience/issues/5688
  def dynamic_actions_workflow?
    dynamic_workflow_integration == "github-actions" || dynamic_workflow_integration == "github-actions-lab"
  end

  def billing_usage_line_items(starting_at, ending_at)
    return @billing_usage_line_items if defined?(@billing_usage_line_items)

    GitHub.dogstats.time("actions.workflows.billing_usage_line_items_workflow_api_timing") do
      line_item_response = billing_client_wrapper.get_usage_line_items(
        product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions],
        usage_starts_at: starting_at,
        usage_ends_at: ending_at,
        custom_fields: { "actions.workflow.id" => { "field_values" => [self.id.to_s] } },
      )

      if line_item_response.is_a?(Billing::Api::ClientWrapper::BillingClientError)
        Failbot.report(StandardError.new("Unable to retrieve line item from Billing Client for workflow"),
          "exception.message": line_item_response.message,
          "gh.actions.workflow.id": self.id,
          "gh.repo.id": repository.id,
          "gh.actions.billing.started_at": starting_at,
          "gh.actions.billing.ending_at": ending_at
        )
        []
      else
        @billing_usage_line_items = line_item_response.map do |usage_line_item|
          Billing::Actions::UsageLineItemWrapper.new(usage_line_item)
        end
      end
    end
  end

  def billing_client_wrapper
    return @billing_client_wrapper if defined?(@billing_client_wrapper)

    owner = repository.owner
    @billing_client_wrapper = Billing::Api::ClientWrapper.new(
      billable_owner: owner.billable_owner,
      owner: owner.is_organization_billed_through_business? ? owner : nil,
    )
  end

  def async_has_workflow_dispatch_trigger?
    repository.async_network.then do
      has_workflow_dispatch_trigger? || false
    end
  end

  def async_has_workflow_dispatch_trigger_for_branch(branch_ref: nil)
    repository.async_network.then do
      Actions::ParsedWorkflow.parse_from_yaml(repository, path, branch_ref)&.has_workflow_dispatch_trigger? || false
    end
  end

  def has_workflow_dispatch_trigger?
    parsed_workflow&.has_workflow_dispatch_trigger?
  end

  def disabled?
    return false unless disableable?

    disabled_fork? || disabled_inactivity? || disabled_manually?
  end

  def disableable?
    # Dynamic workflows are queued on demand by integrators,
    # Launch doesn't check if those workflows are disabled
    return false if dynamic? || required?
    true
  end

  def permalink(include_host: true)
    query_string      = lab? ? "?lab=true" : ""
    url_safe_filename = Addressable::URI.encode_component(filename, Addressable::URI::CharacterClasses::PATH)

    "#{repository.permalink(include_host: include_host)}/actions/workflows/#{url_safe_filename}#{query_string}"
  end

  def self.create_or_update_workflow(workflow_file_path, name, repository, state, event = nil, present_in_default_branch: nil, imposer_repository_id: nil)
    path = workflow_file_path || ""
    workflow_name = name || ""
    imposer_repo_id = imposer_repository_id.nil? ? 0 : imposer_repository_id.to_i
    attrs = { path: path, repository_id: repository.id, imposer_repository_id: imposer_repo_id }
    state = state || "active"

    Actions::Workflow.retry_on_find_or_create_error do
      workflow = Actions::Workflow.find_by(attrs)
      if workflow.nil?
        workflow = Actions::Workflow.new(attrs)
        present_in_default_branch = repository.includes_file?(workflow_file_path) if present_in_default_branch.nil?
      end
      # determine present_in_default_branch if creating a new workflow, update only if value passed in
      workflow.present_in_default_branch = present_in_default_branch unless present_in_default_branch.nil?
      workflow.name = workflow_name

      # Will always be zero in case of workflows other than required workflows.
      # For required workflows, this points to the id of the repository that
      # holds the workflow file's blob.
      workflow.imposer_repository_id = imposer_repo_id

      # State should be only changed here for non required workflow file paths, because
      # we expect required workflows to have any path in a repository.
      if imposer_repo_id == 0
        state = "deleted" unless workflow_file_path.start_with?(WORKFLOWS_BASE_PATH, DYNAMIC_BASE_PATH)
      end

      # warning email state is saved using a key/value pair in GitHub kv that expires when the workflow is completly disabled
      # disabled email state is kept track using the workflow.state property
      disabled_email_needed = false

      # fair usage enforcement, workflow state must be saved before any email is sent
      if public_and_scheduled?(event, repository)
        if !GitHub.enterprise? && workflow.latest_timestamp < REPOSITORY_INACTIVITY_THRESHOLD.days.ago
          state = "disabled_inactivity"
          disabled_email_needed = true if state != workflow.state
        end
      end

      workflow.state = state
      workflow.save!

      if !GitHub.enterprise? && public_and_scheduled?(event, repository)
        # send warning email notification if needed
        workflow.send_inactivity_warning_email if workflow.within_churning_threshold? && state != "disabled_inactivity" && !disabled_email_needed
        # send email notification when the workflow is disabled
        workflow.send_inactivity_disabled_email if disabled_email_needed
      end

      workflow.delete_scheduled_workflow_in_launch(repository, workflow_file_path) if disabled_email_needed

      workflow
    end
  end

  def enable(actor)
    raise CannotBeEnabledError unless disabled? || churning? || active?

    update(state: "active", enabled_at: Time.zone.now)
    GitHub.instrument "workflows.enable_workflow", event_payload(actor)

    # if a scheduled workflow is being enabled, launch must be informed
    if scheduled?
      synchronize_scheduled_workflow_in_launch(repository, actor)
    end
  end

  def disable(actor)
    raise NotActiveError unless active?
    raise CannotBeDisabledError unless disableable?

    update(state: "disabled_manually")
    GitHub.instrument "workflows.disable_workflow", event_payload(actor)

    # if a scheduled workflow is being disabled, launch must be informed
    if scheduled?
      delete_scheduled_workflow_in_launch(repository, path)
    end
  end

  def event_payload(actor)
    payload = {
      actor: actor,
      repo: repository,
      workflow: self,
    }
    payload.tap do |p|
      p[:org] = repository.organization unless repository.organization.nil?
      p[:business] = repository.business unless repository.business.nil?
    end
  end

  def send_inactivity_warning_email
    return if inactivity_warning_email_sent?

    ActionsMailer.workflow_inactivity(repository.owner, self).deliver_later
    mark_warning_email_sent
  end

  def send_inactivity_disabled_email
    ActionsMailer.workflow_inactivity(repository.owner, self, disabled: true).deliver_later
  end

  # repository pushed_at takes into account any push events and is not inclusive to just activity on the default branch
  def latest_timestamp
    [repository.updated_at, repository.pushed_at, enabled_at].compact.max
  end

  def within_churning_threshold?
    latest_timestamp < (REPOSITORY_INACTIVITY_THRESHOLD - INACTIVITY_WARNING_WINDOW).days.ago
  end

  def churning?
    return false unless !GitHub.enterprise?
    return false unless repository.public
    return false unless within_churning_threshold?

    parsed_workflow&.has_schedule_trigger?
  end

  def delete_if_no_runs
    return if workflow_runs.any?
    return if has_workflow_dispatch_trigger?

    GitHub.dogstats.increment("actions.workflow_deleted_no_runs")
    update(state: "deleted")
  end

  def parsed_workflow
    if required?
      @parsed_workflow ||= parsed_required_workflow
    else
      @parsed_workflow ||= Actions::ParsedWorkflow.parse_from_yaml(repository, path)
    end
  end

  def file_size
    parsed_workflow&.file_size
  end

  def scheduled?
    parsed_workflow&.has_schedule_trigger?
  end

  def trigger_events
    parsed_workflow&.trigger_events
  end

  def delete_scheduled_workflow_in_launch(repo, workflow_file_path)
    # when disabling a scheduled workflow, the actor is not needed
    publish_state_change_hydro_event(nil)
  end

  def synchronize_scheduled_workflow_in_launch(repo, actor)
    publish_state_change_hydro_event(actor)
  end

  def spammy?
    return false unless GitHub.spamminess_check_enabled?
    return false if present_in_default_branch?
    workflow_runs.not_spammy.none?
  end

  def pin(actor)
    raise AlreadyPinnedError if is_pinned?
    raise MaxPinnedWorkflowsReachedError if Actions::PinnedWorkflow.limit_reached?(repository.id)
    raise CannotPinInactiveWorkflowError if !active?
    raise UserCannotPinWorkflowError unless Actions::PinnedWorkflow::user_can_pin_workflows?(repository, actor)

    Actions::PinnedWorkflow.create(workflow_id: id, repository_id: repository.id, pinned_by: actor)
    publish_pinning_activity_hydro_event(actor, "PINNED")
    GitHub.instrument "workflows.pin_workflow", event_payload(actor)
  end

  def unpin(actor)
    raise AlreadyUnpinnedError unless is_pinned?
    raise UserCannotPinWorkflowError unless Actions::PinnedWorkflow::user_can_pin_workflows?(repository, actor)

    pinned_workflow.destroy
    publish_pinning_activity_hydro_event(actor, "UNPINNED")
    GitHub.instrument "workflows.unpin_workflow", event_payload(actor)
  end

  def is_pinned?
    !!pinned_workflow
  end

  private

  # Public: Was the state changed in previous_changes? We use this to determine
  # if state changes _only_ after_commit.
  # When the state is changed to active we want to also send the `actor` which is
  # available in the `enable` method
  def state_changed_from_active_after_commit?
    previous_changes.key?(:state) && previous_changes[:state].include?(:active.to_s)
  end

  def create_sequence
    Sequence.create(self)
  end

  def update_timestamps
    if disabled?
      self.disabled_at = Time.zone.now
      self.enabled_at = nil
    elsif active?
      self.disabled_at = nil
      self.enabled_at = Time.zone.now
    end
  end

  def unpin_inactive
    # This is the same a unpin() expect there is no audit log created
    if is_pinned? && !active?
      pinned_workflow.destroy
      publish_pinning_activity_hydro_event(nil, "UNPINNED")
    end
  end

  def publish_state_change_hydro_event(actor)
    env = lab? ? "lab" : "production"
    ref = "refs/heads/#{repository.default_branch}"
    message = {
      workflow_id: id,
      branch_ref: ref,
      installation_id: GitHub.launch_github_app.installations_on(repository.owner)&.with_repository(repository)&.first&.id,
      environment: env,
      actor: Hydro::EntitySerializer.user(actor),
      repository: Hydro::EntitySerializer.repository(repository),
      workflow_file_path: path,
      workflow_state: state.to_s.upcase,
    }

    Hydro::PublishRetrier.publish(message, schema: "github.actions.v0.WorkflowStateChange", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  def publish_pinning_activity_hydro_event(actor, event)
    raise ArgumentError, "Invalid pinning event: #{event}. Event must be either 'PINNED' or 'UNPINNED'." unless %w(PINNED UNPINNED).include?(event)
    GlobalInstrumenter.instrument("workflow.pinning_activity", {
      workflow_id: id,
      actor_id: actor&.id,
      workflow_repository_id: repository.id,
      event: event,
    })
  end

  # example key: inactive-workflow-warning-123-4, changing this key could result in duplicate emails
  def workflow_email_inactivity_warning_key
    ["inactive-workflow-warning", repository.id, id].compact.join("-")
  end

  def inactivity_warning_email_sent?
    kv(repository_id).exists(workflow_email_inactivity_warning_key).value { false }
  end

  def mark_warning_email_sent
    ActiveRecord::Base.connected_to(role: :writing) do
      kv(repository_id).set(workflow_email_inactivity_warning_key, "true", expires: REPOSITORY_INACTIVITY_THRESHOLD.days.from_now)
    end
  end

  def dynamic?
    path.start_with?(DYNAMIC_BASE_PATH)
  end

  def dynamic_workflow_integration
    return @dynamic_workflow_integration if defined?(@dynamic_workflow_integration)

    # Expect filename to be in the format integration/slug
    @dynamic_workflow_integration = filename.split("/").first if dynamic?
    @dynamic_workflow_integration ||= ""
  end

  def parsed_required_workflow
    source_repo = required_workflow_source_repo
    return if source_repo.nil?

    Actions::ParsedWorkflow.parse_from_yaml(source_repo, path)
  end

  def required_workflow_source_repo
    Repository.find_by(id: imposer_repository_id)
  end

  def kv(repository_id)
    Actions::KV.for_partition_key(repository_id)
  end
end
