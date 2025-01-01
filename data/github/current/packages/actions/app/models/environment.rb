# typed: false
# frozen_string_literal: true

class Environment < ApplicationRecord::ActionsEnvironments
  include Environment::PinDependency
  include GitHub::Validations
  include Instrumentation::Model
  include GitHub::FlipperActor
  include GitHub::VexiActor

  after_commit :instrument_destruction, on: :destroy
  after_commit :instrument_creation, on: :create

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  destroy_in_background_with :repository

  validates_presence_of :name
  validates :name, comparison: { other_than: ".", message: "must be other than \".\", \"..\", or \"~\"" }, on: :create, allow_blank: true
  validates :name, comparison: { other_than: "..", message: "must be other than \".\", \"..\", or \"~\"" }, on: :create, allow_blank: true
  validates :name, comparison: { other_than: "~", message: "must be other than \".\", \"..\", or \"~\"" }, on: :create, allow_blank: true
  validates_length_of :name, maximum: 255
  validate :validate_name_format, on: :create
  validates_uniqueness_of :name, scope: [:repository], case_sensitive: false, if: -> { errors[:name].blank? }

  before_validation :normalize_environment_name

  has_one :pinned_environment, dependent: :destroy
  has_many :gates, autosave: true
  has_many :custom_gates, -> { where(type: :custom) },
    class_name: "Gate"

  has_many :custom_gate_integrations,
    through: :custom_gates,
    class_name: "Integration",
    source: :integration,
    disable_joins: true

  class EnvironmentError < StandardError; end

  def event_prefix() :environment end

  def event_payload
    {
      event_prefix => self,
      "public_repo".to_sym => repository&.public?,
    }
  end

  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      "#{prefix}_name".to_sym => name,
    }
  end

  def latest_completed_deployment
    Deployment.where(repository: repository, latest_status_state: %w[success failure error], latest_environment: name).first
  end

  # Add a manual approver to this environment.
  #
  # Environments can only have a single manual approval gate, so we simplify
  # adding approvers by finding-or-creating the one approval gate for this
  # environment.
  #
  # Returns the approver or nil on error.
  def add_approver(approver)
    should_log_update = has_approval_gate?
    approvers_was = []

    gate_approver = transaction do
      gate = gates.retry_on_find_or_create_error do
        approval_gate || gates.create(type: :manual_approval, timeout: 0)
      end

      approvers_was = gate.gate_approvers.includes(:approver).collect(&:approver)
      gate_approver = gate.gate_approvers.find_by(approver: approver)
      if gate_approver
        should_log_update = false
      else
        gate_approver = GateApprover.create(gate: gate, repository: repository, approver: approver)
        raise ActiveRecord::Rollback unless gate_approver.persisted?
      end

      gate_approver
    end

    instrument_event(
      event: "update_protection_rule",
      gate_type: "manual_approval",
      approvers_was: approvers_was,
      approvers: approvers_was + [approver]
    ) if should_log_update
    gate_approver
  end

  # Remove a manual approver from this environment.
  #
  # Returns true on success (or when unnecessary), or nil on error.
  def remove_approver(approver)
    gate = approval_gate or return true
    should_log_update = true
    approvers_was = []

    success = gate.transaction do
      approvers_was = gate.gate_approvers.includes(:approver).collect(&:approver)
      gate_approver = gate.gate_approvers.find_by(approver: approver)
      success = gate_approver.destroy
      raise ActiveRecord::Rollback unless success

      if gate.gate_approvers.empty?
        should_log_update = false
        success = gate.destroy
        raise ActiveRecord::Rollback unless success
      end

      success
    end

    instrument_event(
      event: "update_protection_rule",
      gate_type: "manual_approval",
      approvers_was: approvers_was,
      approvers: approvers_was - [approver]
    ) if should_log_update
    success
  end

  def has_approval_gate?
    gates.exists?(type: :manual_approval)
  end

  def approval_gate
    gates.find_by(type: :manual_approval)
  end

  def is_pinned?
    PinnedEnvironment.where(repository: repository, environment_id: id).any?
  end

  def pinned_position
    PinnedEnvironment.where(repository: repository, environment_id: id).first&.position
  end

  def create_or_update_approval_gate(approvers, prevent_self_review: false, prevent_self_review_changed: false)
    # nil check for approvers because the value could be nil if changing prevent_self_review value without changing approvers
    if approvers && approvers.length > Gate::MAX_APPROVERS
      errors.add(:base, "Failed to create the environment protection rule. Required reviewers can have at most #{Gate::MAX_APPROVERS} reviewers.")
      return
    elsif approvers&.empty?
      errors.add(:base, "Failed to create the environment protection rule. Required reviewers must have at least one reviewer.")
      return
    end

    approvers_was = []
    should_log_update = has_approval_gate?
    gate = transaction do
      gate = gates.retry_on_find_or_create_error do
        approval_gate || gates.create(type: :manual_approval, timeout: 0)
      end

      if approvers
        if gate.gate_approvers.pluck(:approver_id).sort != approvers.pluck(:id).sort
          approvers_was = gate.gate_approvers.includes(:approver).collect(&:approver)
          gate.set_approvers(approvers)
        end
      end

      # check if trying to create the gate with setting prevent_self_review as false when there are no approvers
      if gate.gate_approvers.empty? && !prevent_self_review.nil? && !prevent_self_review && prevent_self_review_changed
        errors.add(:base, "Failed to create or update the environment protection rule. Required reviewers must have at least one reviewer to set prevent_self_review.")
        raise ActiveRecord::Rollback
      end
      if !prevent_self_review.nil? && gate.prevent_self_review != prevent_self_review
        if gate.gate_approvers.empty?
          errors.add(:base, "Failed to create or update the environment protection rule. Required reviewers must have at least one reviewer to set prevent_self_review.")
          raise ActiveRecord::Rollback
        end
        gate.prevent_self_review = prevent_self_review
        gate.save!
      end
      gate
    end

    instrument_event(
      event: "update_protection_rule",
      gate_type: "manual_approval",
      approvers_was: approvers_was,
      approvers: approvers,
      prevent_self_review: prevent_self_review) if should_log_update
    gate
  end

  def remove_approval_gate
    gate = approval_gate
    return unless gate

    gate.destroy
  end

  def create_or_update_custom_protection_rules(integration_ids)
    if integration_ids.empty?
      gates.where(type: :custom).destroy_all
      return
    end

    transaction do
      custom_gates = gates.where(type: :custom).to_a

      existing, to_delete = custom_gates.partition { |g| integration_ids.include?(g.integration_id) }
      Gate.destroy(to_delete.map(&:id))

      to_add = integration_ids - existing.map(&:integration_id)
      next unless to_add.any?

      # retrieve installed integrations that could be used as gates
      integrations = IntegrationInstallation
        .with_repository(repository)
        .includes(:event_records)
        .filter { |i| i.event_records.map(&:name).include?("deployment_protection_rule") }
        .map(&:integration_id)

      # filter to_add to only include installed integrations
      # incase the user tried to pass in an integration that isn't installed
      to_add = to_add
        .filter { |id| integrations.include?(id) }
        .map { |id| { type: :custom, integration_id: id } }
      gates.create(to_add)
    end
  end

  def custom_app_integrations
    installations = IntegrationInstallation
      .with_repository(repository)
      .includes(:event_records)
      .includes(:integration)

    installations.filter { |i| i.event_records.map(&:name).include?("deployment_protection_rule") && !i.suspended? }.map(&:integration)
  end

  def custom_protection_rules
    enabled_integrations = custom_gates # integration may be deleted
    valid_integrations = custom_app_integrations.compact # remove potentially nil integrations

    integration_ids = enabled_integrations.pluck(:integration_id)
      .concat(valid_integrations.pluck(:id))
      .uniq
    integrations = enabled_integrations.map(&:integration)
      .concat(valid_integrations)
      .compact
      .uniq

    return [] unless integration_ids.any?

    integration_ids.map do |integration_id| {
        integration_id: integration_id,
        integration: integrations.find { |i| i.id == integration_id },
        enabled: enabled_integrations.map(&:integration_id).include?(integration_id),
        invalid: !valid_integrations.map(&:id).include?(integration_id)
      }
    end
  end

  def available_disabled_custom_gate_apps
    apps = custom_app_integrations
    integration_ids = apps.map(&:id)

    enabled_custom_gate_integration_ids = custom_gates&.map(&:integration_id)

    apps.reject { |app| enabled_custom_gate_integration_ids.include?(app.id) }
  end

  def create_or_update_wait_gate(timeout)
    if timeout.to_i > Gate::MAX_TIMEOUT_MINUTES
      errors.add(:base, "Failed to create the environment protection rule. The wait timer cannot be greater than #{Gate::MAX_TIMEOUT_MINUTES} minutes.")
      return
    end

    gate = gates.retry_on_find_or_create_error do
      wait_gate || gates.create(type: :timeout, timeout: timeout)
    end

    timeout_was = gate.timeout
    unless timeout_was == timeout.to_i
      gate.update(timeout: timeout)
      instrument_event(event: "update_protection_rule", gate_type: "timeout", timeout_was: timeout_was, timeout: timeout)
    end

    gate
  end

  def remove_wait_gate
    gate = wait_gate
    return unless gate

    gate.destroy
  end

  def has_wait_gate?
    gates.exists?(type: :timeout)
  end

  def wait_gate
    gates.find_by(type: :timeout)
  end

  def create_branch_policy_gate(protected_branch_policy:)
    json_body = {
      Gate::PROTECTED_BRANCHES => protected_branch_policy
    }
    gate = branch_policy_gate

    return if gate.present? && branch_policy_gate_branch_protected? == protected_branch_policy
    if gate.nil?
      instrument_event(event: "add_protection_rule", gate_type: "branch_policy", is_protected_branch_policy: protected_branch_policy)
    else
      instrument_event(event: "update_protection_rule", gate_type: "branch_policy", is_protected_branch_policy: protected_branch_policy)
    end

    gate.destroy if gate
    gates.create(type: :branch_policy, body: JSON[json_body])
  end

  def branch_policy_gate
    gates.find_by(type: :branch_policy)
  end

  def branch_policy_gate_branch_protected?
    gate = branch_policy_gate
    return false unless gate
    gate.protected_branch_gate?
  end

  def remove_branch_policy_gate
    gate = branch_policy_gate
    return unless gate
    instrument_event(event: "remove_protection_rule", gate_type: "branch_policy")
    gate.destroy
  end

  def destroy
    result = transaction do
      result = super()
      # `Gate::destroy` triggers `Gate::reject_pending_gate_requests`, which requires the environment to exist.
      # So, we have to destroy gates *before* the `destroy` method exits.
      # `destroy_dependents_in_background :gates` won't work.
      gates.destroy_all
      result
    end

    # `destroy` may be called when the repository is deleted
    if repository&.can_use_environments?
      BatchInactivateDeploymentsJob.perform_later(repository_id: repository.id, environment: name) if GitHub.actions_enabled?
    end

    result
  end

  def self.create_for_repository(repository_id, name)
    name ||= "production" # the default in the database
    name = name.strip # remove whitespace
    last_insert_id = self.connection.insert(Arel.sql(<<-SQL, repository_id: repository_id, name: name))
      INSERT IGNORE INTO environments (repository_id, name, created_at, updated_at) VALUES (:repository_id, :name, CURRENT_TIME(), CURRENT_TIME())
    SQL

    environment = Environment.find_by(repository_id: repository_id, name: name)
    environment.instrument_creation if environment && last_insert_id > 0
    environment
  end

  def self.create_or_update_environment(repo, data, environment_name)
    environment_name = environment_name.strip # strip whitespace when searching for environment as we strip before inserting into DB.
    environment = repo.environments.includes(:gates).find_by(name: environment_name)

    if environment.nil?
      begin
        environment = Environment.create_for_repository(repo.id, environment_name)
      rescue ActiveRecord::StatementInvalid
        raise Environment::EnvironmentError.new("Unable to create Environment with name '#{environment_name}'")
      end

      raise Environment::EnvironmentError.new("Unable to create Environment with name '#{environment_name}'") if environment.nil?
    end

    if data.key?("reviewers")
      raise Environment::EnvironmentError.new("Failed to create the environment protection rule. Please ensure the billing plan supports the required reviewers protection rule.") unless repo.can_use_deployment_branch_gates?
      approvers = data["reviewers"]
      if approvers.present?
        actors = approvers.map do |info|
          info["type"] == "User" ? User.find(info["id"]) : Team.find(info["id"])
        end
        prevent_self_review = data.key?("prevent_self_review") ? data["prevent_self_review"] : nil
        environment.create_or_update_approval_gate(actors, prevent_self_review: prevent_self_review)
        if environment.errors.present?
          raise Environment::EnvironmentError.new(environment.errors.full_messages.first)
        end
      else
        environment.remove_approval_gate
      end
    end

    if data.key?("wait_timer")
      raise Environment::EnvironmentError.new("Failed to create the environment protection rule. Please ensure the billing plan supports the wait timer protection rule.") unless repo.can_use_deployment_branch_gates?
      timeout = data["wait_timer"]
      if timeout > 0
        environment.create_or_update_wait_gate(timeout)
        if environment.errors.present?
          raise Environment::EnvironmentError.new(environment.errors.full_messages.first)
        end
      else
        environment.remove_wait_gate
      end
    end

    if data.key?("can_admins_bypass")
      bypass_flag = data["can_admins_bypass"]
      if bypass_flag == true
        environment.gates_admin_enforced = false
        if environment.errors.present?
          raise Environment::EnvironmentError.new(environment.errors.full_messages.first)
        end
      elsif bypass_flag == false || bypass_flag.nil?
        environment.gates_admin_enforced = true
      else
        raise Environment::EnvironmentError.new("Invalid value for allow_admins_to_bypass_protection expected true, false or nil")
      end
      environment.save!
      environment.instrument_event(event: "update_protection_rule", can_admins_bypass: environment.gates_admin_enforced)
    end

    if environment.repository.can_use_deployment_protected_branch? && data.key?("deployment_branch_policy")
      deployment_branch_policy = data["deployment_branch_policy"]
      if deployment_branch_policy.present?
        if deployment_branch_policy["custom_branch_policies"] == deployment_branch_policy["protected_branches"]
          raise Environment::EnvironmentError.new("\"custom_branch_policies\" and \"protected_branches\" cannot have the same value")
        end
        environment.create_branch_policy_gate(protected_branch_policy: deployment_branch_policy["protected_branches"])
      else
        environment.remove_branch_policy_gate
      end
    end

    if data.key?("prevent_self_review") && !data.key?("reviewers")
      prevent_self_review = data["prevent_self_review"]
      environment.create_or_update_approval_gate(nil, prevent_self_review: prevent_self_review, prevent_self_review_changed: true)
      if environment.errors.present?
        raise Environment::EnvironmentError.new(environment.errors.full_messages.first)
      end
    end

    environment = repo.environments.includes(:gates).find_by(name: environment_name)
    environment
  end

  def instrument_event(event:, **args)
    audit_payload = args.merge(
      repo: repository,
      actor: actor,
      environment_name: name,
      environment_id: id
    ).tap do |p|
      p[:org] = repository.owner if repository.owner.is_a? Organization
      p[:business] = repository.owner.business if repository.owner.business.present?
    end

    GitHub.instrument "environment.#{event}", audit_payload
  end

  def gates
    # extra filtering to make sure that we dont return gates
    # that the customer is no longer eligible to use
    if repository.nil? || # can't do any of these checks if repo doesnt exist
      repository.can_use_deployment_branch_gates? # enterprise can use all gate types
      super
    elsif repository.can_use_deployment_protected_branch?
      # pro & team (and free currently FF'ed) can only use branch policy
      super.where(type: "branch_policy")
    else
      super
    end
  end

  # This exists to match twirp call with graphql call, see https://github.com/github/github/blob/330f8347a5e5e10691e2db9f0b72f6acdb526ff7/app/platform/objects/environment.rb#L70-L73
  def gates_for_twirp
    if repository&.can_use_environments?
      gates
    else
      ::Gate.none
    end
  end

  def calculate_remaining_allowed_reviewers
    Gate::MAX_APPROVERS - (has_approval_gate? ? approval_gate.gate_approvers.size : 0)
  end

  def calculate_reviewers_invisible_to_user(user)
    count = 0
    if has_approval_gate?
      approval_gate.gate_approvers.each do |gate_approver|
        count += 1 unless gate_approver.approver&.is_a?(User) || gate_approver.approver&.visible_to?(user)
      end
    end
    count
  end

  def instrument_creation
    instrument_event(event: "create")
  end

  # Returns true if admins can bypass the environment protection rules for the environment
  def can_admins_bypass?
    !gates_admin_enforced
  end

  private

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the ghost user.
  def actor
    @actor ||= User.find_by_id(GitHub.context[:actor_id])
  end

  def instrument_destruction
    # If the repository is being deleted, it's customary to skip dependent deletes
    # in the audit log to reduce noise.
    # As written, the code will fail if the repository is missing anyway.
    return if repository.nil?
    instrument_event(event: "delete")

    # Emit EnvironmentDeleted event to delete any secrets
    GlobalInstrumenter.instrument "environment.deleted", {
      actor: actor,
      deleted_environment: self,
    }
  end

  def normalize_environment_name
    return unless name
    self.name = name.strip.presence
  end

  INVALID_NAME_CHARS = ["'", '"', "`", ",", ";", "\\"]
  def validate_name_format
    return if name.nil?

    non_printable_chars = name.scan(/[^[:print:]]/).uniq
    if non_printable_chars.present? || INVALID_NAME_CHARS.any? { |c| name.include?(c) }
      invalid_name_chars_string = INVALID_NAME_CHARS.map(&:inspect).join(", ")
      non_printable_chars_string = non_printable_chars.map(&:inspect).join(", ")

      if non_printable_chars_string.present?
        non_printable_chars_string = " (#{non_printable_chars_string})"
      end

      errors.add("name", "must not contain non-printable characters#{non_printable_chars_string} or the characters #{invalid_name_chars_string}")
    end
  end
end
