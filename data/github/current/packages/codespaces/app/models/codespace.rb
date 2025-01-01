# typed: true
# frozen_string_literal: true

require "hashids"

class Codespace < ApplicationRecord::Domain::Codespaces
  include GitHub::ResilienceMixin
  include Instrumentation::Model
  include Ability::Subject
  include Codespaces::LinkedResourcesDependency
  include Codespaces::VscsTargetDependency
  include Repositories::BelongsToRepository
  include GitHub::Memoizer

  self.table_name = "workspaces"
  self.strict_loading_by_default = true

  MAX_NAME_GENERATION_ATTEMPTS = 100

  # The name must be a valid domain name label, in both format and length.
  NAME_ALLOWED_CHARS_REGEX = /[a-z0-9\-]/i
  # Max length is 63 but we shall give a window for max. port suffix (e.g: `-65535`)
  MAX_NAME_LENGTH = 57
  NAME_REGEX = /\A[^\-]#{NAME_ALLOWED_CHARS_REGEX}{1,#{MAX_NAME_LENGTH}}[^\-]\z/
  MAX_NAME_LENGTH_EXISTING_RECORD = 63
  NAME_REGEX_EXISTING_RECORD = /\A[^\-]#{NAME_ALLOWED_CHARS_REGEX}{1,#{MAX_NAME_LENGTH_EXISTING_RECORD}}[^\-]\z/

  MAX_RETENTION_PERIOD = 30.days.in_minutes.to_i

  EXPORT_BRANCH_PREFIX = "codespace-"
  EXPORT_STATE_SUCCEEDED = "succeeded"
  EXPORT_STATE_FAILED = "failed"
  EXPORT_STATE_IN_PROGRESS = "in_progress"
  EXPORT_STATE_NO_EXPORT_EXISTS = "no_export_exists"

  # used on the GraphQL API to return a value when we have no `State` in `environment_data`
  VSCS_STATE_UNKNOWN = "Unknown"

  STUCK_STATE_MINUTES = 5.minutes

  RESTORABLE_PERIOD = 7.days

  EPHEMERAL_CLOUDSPACE_ID = "ephemeral"

  extend GitHub::Encoding
  force_utf8_encoding :ref

  belongs_to_repository_via_domain class_name: "::Repository", strict_loading: false
  belongs_to :owner, class_name: "::User", strict_loading: false
  belongs_to :pull_request, class_name: "::PullRequest", strict_loading: false
  belongs_to :plan, class_name: "Codespaces::Plan", validate: true, autosave: true, strict_loading: false
  belongs_to :billable_owner, polymorphic: true, strict_loading: false
  belongs_to :template_repository, class_name: "::Repository", strict_loading: false, optional: true

  # rubocop:todo Rails/InverseOf
  has_one :billing_entry, -> { order(id: :desc) },
    validate: true,
    class_name: "Codespaces::BillingEntry",
    foreign_key: :codespace_guid,
    primary_key: :guid,
    strict_loading: false
  # rubocop:enable Rails/InverseOf

  has_many :async_operations,
    class_name: "Codespaces::AsyncOperation",
    dependent: :destroy,
    strict_loading: false

  has_many :pending_async_operations,
    -> { pending },
    class_name: "Codespaces::AsyncOperation",
    strict_loading: false

  has_many :blocking_pending_async_operations,
    -> { Codespaces::AsyncOperation.pending.blocking },
    class_name: "Codespaces::AsyncOperation",
    strict_loading: false

  has_many :codespaces_site_scoped_integration_installations,
    strict_loading: false

  destroy_dependents_in_background :codespaces_site_scoped_integration_installations

  enum :state, %i{
    pending
    provisioning
    provisioned
    failed
    deprovisioning
    deprovisioned
  }

  # Newly supported skus with billing rates should also be added to Codespaces::Skus::RATES
  enum :sku_name, {
    basicLinux: 0,
    standardLinux: 1,
    premiumLinux: 2,
    standardLinux32gb: 9,
    basicLinux32gb: 10,
    premiumLinux32gb: 11,

    prototypePremiumLinux: 13,
    extremeLinux: 14,
    standardLinuxAMD: 15,
    largePremiumLinux: 16,
    xLargePremiumLinux: 17,
    premiumLinuxGPU: 18,
    standardLinuxNcv3: 19,

    ExperimentalLinux1: 20,
    ExperimentalLinux2: 21,
    ExperimentalLinux3: 22,
    ExperimentalLinux4: 23,
    ExperimentalLinux5: 24,
    ExperimentalLinux6: 25,
    ExperimentalLinux7: 26,
    ExperimentalLinux8: 27,
    ExperimentalLinux9: 28,
    ExperimentalLinux10: 29,

    largePremiumLinux256gb: 30,
    xLargePremiumLinux256gb: 31
  }

  enum :deletion_reason, {
    bulk_dependent_deletion: "bulk_dependent_deletion", # deleted by DeleteDependentCodespacesJob legacy
    bulk_dependent_deletion_spammy: "bulk_dependent_deletion_spammy", # deleted by DeleteDependentCodespacesJob for spammy user
    bulk_dependent_deletion_user: "bulk_dependent_deletion_user", # deleted by DeleteDependentCodespacesJob for user deletion
    dependent_never_available: "dependent_never_available", # deleted when codespace never came out of provisioning
    inaccessible: "inaccessible", # deleted when codespace is no longer accessible by owner
    lost_repo_access: "lost_repo_access",
    org_admin_requested: "org_admin_requested",
    org_disabled_codespaces: "org_disabled_codespaces", # org disabled codespaces org-wide
    org_disabled_for_repo: "org_disabled_for_repo", # org removed repo from selected repositories enabled
    org_disabled_for_user: "org_disabled_for_user", # org disabled codespaces for an individual
    org_downgrade: "org_downgrade", # org switched to a free plan
    process_system_event: "process_system_event", # fallback reason for any deletion that happens in ProcessSystemEvent
    repository_made_private: "repository_made_private",
    repository_removed: "repository_removed",
    retention_period: "retention_period",
    stafftools_requested: "stafftools_requested",
    user_requested: "user_requested",
    stuck_provisioning: "stuck_provisioning", # deleted by CleanUpStuckProvisioningJob
    service_provisioning_failed: "service_provisioning_failed", # we received a webhook from the service that provisioning failed
  }, suffix: true

  attribute :environment_data, Codespaces::Environment::Type.new

  validates :owner, presence: true, unless: -> { T.bind(self, Codespace); deprovisioning? || deprovisioned? }
  validates :location, :name, :oid, :ref, :sku_name, presence: true
  validates :plan, presence: true, if: -> { T.bind(self, Codespace); provisioned? }
  validates :guid, length: { is: 36 }, allow_nil: true
  validates :name, format: { with: NAME_REGEX }, unless: -> { T.bind(self, Codespace); deprovisioning? }, on: :create
  # We have existing repositories with name length > MAX_NAME_LENGTH already
  # we need to use a different validation with more allowed length (i.e: MAX_NAME_LENGTH_EXISTING_RECORD)
  # TODO: remove this validation after fixing the long names:
  # - https://github.com/github/github/pull/181907 (or any other related work)
  validates :name, format: { with: NAME_REGEX_EXISTING_RECORD }, unless: -> { T.bind(self, Codespace); deprovisioning? }, on: :update
  validates :oid, length: { is: 40 }
  validates :billing_entry, presence: true, if: -> { T.bind(self, Codespace); provisioned? }
  validates :display_name, length: { maximum: 48 }, allow_nil: true

  validates :devcontainer_path, format: { with: Codespaces::DevContainer::VALID_DEVCONTAINER_PATH_GLOB }, allow_nil: true
  validates :retention_period_minutes, numericality: {
    allow_nil: true,
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: Codespace::MAX_RETENTION_PERIOD,
    message: "must be between 0 and #{Codespace::MAX_RETENTION_PERIOD}"
  }
  validate :valid_local_target_url, if: -> { T.bind(self, Codespace); vscs_target&.to_sym == :local }
  validate :ensure_valid_state_for_guid
  validate :valid_environment_data
  validate :ensure_repository_id

  # generate the codespace name.
  before_validation :generate_names, on: :create
  # must come last since other callbacks set attributes used too
  before_validation :set_initial_last_used_at, on: :create
  before_validation :set_codespace_billing_entry, if: -> { T.bind(self, Codespace); provisioned? }

  before_destroy :destroy_requires_deprovisioning
  after_commit :instrument_creation, on: :create
  after_commit :instrument_destroy, on: :destroy
  after_commit :notify_socket_subscribers, on: [:create, :destroy]
  after_commit :instrument_pull_request_updated, if: :pull_request_previously_changed?
  after_commit :instrument_repository_changed, if: :repository_previously_changed?, on: :update

  default_scope { active }

  scope :active, -> { where(deleted_at: nil) }
  scope :include_deleted, -> { unscope(where: :deleted_at) }
  scope :deleted, -> { include_deleted.where.not(deleted_at: nil) }
  scope :purgable, -> { include_deleted.where("deleted_at < now() - interval ? second", RESTORABLE_PERIOD.in_seconds) }

  scope :only_codespaces, -> {
    where(copilot_workspace_id: nil)
    .where("linked_resources->'$.spark_workbench_id' IS NULL")
  }
  scope :only_copilot_workspace, -> { where.not(copilot_workspace_id: [nil, WorkspaceEditor::Cloudspace::COPILOT_WORKSPACE_ID]) }
  scope :only_ephemeral_cloud_environments, -> { where(copilot_workspace_id: EPHEMERAL_CLOUDSPACE_ID) }
  scope :only_workspace_editor_cloud_environments, -> { where(copilot_workspace_id: WorkspaceEditor::Cloudspace::COPILOT_WORKSPACE_ID) }

  # extracts spark_id from JSON string linked_resources
  scope :only_workbench_cloud_environments, -> {
    where.not(linked_resources: nil)
    .where("linked_resources->'$.spark_workbench_id' IS NOT NULL")
  }

  scope :by_recently_used, -> { order(last_used_at: :desc) }
  scope :by_recently_deleted, -> { order(deleted_at: :desc) }
  scope :in_legacy_resource_provider, -> {
    joins(:plan).merge(Codespaces::Plan.with_legacy_resource_provider)
  }

  scope :for_organization, -> (organization) { where(billable_owner: organization) }
  scope :past_retention, -> { active.where("retention_expires_at < now()") }
  scope :stuck_provisioning, -> { where(state: [:pending, :provisioning, :failed]).where("created_at < ?", STUCK_STATE_MINUTES.ago) }

  scope :deprovisionable_by, -> (user) { where(owner: user).where.not(state: :deprovisioning).where("environment_data NOT LIKE '%\"hasUnpushedChanges\": true%'").where("environment_data NOT LIKE '%\"hasUncommittedChanges\": true%'") }

  scope :consuming_compute, -> { where("environment_data->'$.state' IN (?)", Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES) }

  # Public: Scopes codespaces to only those the viewer has at least pull
  # access on the associated repository.
  #
  # WARNING: This scope should only be called on already narrowly scoped ActiveRelation chains.
  # When multiple conditions are used, add this last in the query chain to limit the scope
  # of the additional queries needed.
  #
  # viewer - The user to scope the codespaces for.
  # include_all_cloudspaces - whether to include all cloudspaces (e.g. Spark, Codespaces), rather than only those created from the Codespaces experience. Defaults to false.
  #
  # Returns an ActiveRelation scope.
  def self.visible_to(viewer, include_all_cloudspaces: false)
    query = not_deprovisioning

    unless include_all_cloudspaces
      query = query.only_codespaces
    end

    query.then do |scope|
      # Ensure we use the cached/resolved RepositoryPolicy so that we don't have to resolve all of these sequentially.
      policy_cache = Codespaces::MultiRepositoryPolicyCache.new(scope)
      where(id: scope.filter { _1.accessible?(repository_policy: policy_cache.get(_1)) }.map(&:id))
    end
  end

  # Public: Scopes CWTP codespaces to only those the viewer has at least pull
  # access on the associated repository.
  #
  # This is a copy of the scoping method above, only instead of filtering out CWTP codespaces,
  # it only includes CWTP codespaces.
  #
  # WARNING: This scope should only be called on already narrowly scoped ActiveRelation chains.
  # When multiple conditions are used, add this last in the query chain to limit the scope
  # of the additional queries needed.
  #
  # CALL IT LIKE THIS:
  # viewer.codespaces.visible_to_copilot_workspace(viewer)
  #
  # viewer - The user to scope the codespaces for.
  #
  # Returns an ActiveRelation scope.
  def self.visible_to_copilot_workspace(viewer)
    return none unless viewer.spark_enabled?
    not_deprovisioning.only_copilot_workspace.then do |scope|
      # Ensure we use the cached/resolved RepositoryPolicy so that we don't have to resolve all of these sequentially.
      policy_cache = Codespaces::MultiRepositoryPolicyCache.new(scope)
      where(id: scope.filter { _1.accessible?(repository_policy: policy_cache.get(_1)) }.map(&:id))
    end
  end

  # Public: Scopes ephemeral codespaces to only those the viewer has at least pull
  # access on the associated repository.
  #
  # This is a copy of the scoping method above, only instead of filtering out ephemeral codespaces,
  # it only includes ephemeral codespaces.
  #
  # WARNING: This scope should only be called on already narrowly scoped ActiveRelation chains.
  # When multiple conditions are used, add this last in the query chain to limit the scope
  # of the additional queries needed.
  #
  # CALL IT LIKE THIS:
  # viewer.codespaces.visible_to_ephemeral_cloud_environments(viewer)
  #
  # viewer - The user to scope the codespaces for.
  #
  # Returns an ActiveRelation scope.
  def self.visible_to_ephemeral_cloud_environments(viewer)
    return none unless viewer.spark_enabled?
    not_deprovisioning.only_ephemeral_cloud_environments.then do |scope|
      # Ensure we use the cached/resolved RepositoryPolicy so that we don't have to resolve all of these sequentially.
      policy_cache = Codespaces::MultiRepositoryPolicyCache.new(scope)
      where(id: scope.filter { _1.accessible?(repository_policy: policy_cache.get(_1)) }.map(&:id))
    end
  end

  # Public: Scopes workspace editor cloudspaces to only those the viewer has at least pull
  # access on the associated repository.
  #
  # This is a copy of the scoping method above, but only includes workspace editor cloudspaces.
  #
  # WARNING: This scope should only be called on already narrowly scoped ActiveRelation chains.
  # When multiple conditions are used, add this last in the query chain to limit the scope
  # of the additional queries needed.
  #
  # CALL IT LIKE THIS:
  # viewer.codespaces.visible_to_workspace_editor_cloud_environments(viewer)
  #
  # viewer - The user to scope the codespaces for.
  #
  # Returns an ActiveRelation scope.
  def self.visible_to_workspace_editor_cloud_environments(viewer, repository: nil, skip_access_check: false)
    unless skip_access_check
      return none unless viewer.workspace_editor_preview_enabled?(repository: repository)
    end

    not_deprovisioning.only_workspace_editor_cloud_environments.then do |scope|
      # Ensure we use the cached/resolved RepositoryPolicy so that we don't have to resolve all of these sequentially.
      policy_cache = Codespaces::MultiRepositoryPolicyCache.new(scope)
      where(id: scope.filter { _1.accessible?(repository_policy: policy_cache.get(_1)) }.map(&:id))
    end
  end

  # TODO: Added this scope to narrow down the codespaces to what the user can see. Since Sparks don't necessarily have
  # a repository, this may hit a snag with the repository_policy check requiring PR access.
  #
  # Public: Scopes workbench cloudspaces to only the viewer/owner of the Spark.
  #
  # This is a copy of the scoping method above, but only includes workbench cloudspaces.
  #
  # WARNING: This scope should only be called on already narrowly scoped ActiveRelation chains.
  # When multiple conditions are used, add this last in the query chain to limit the scope
  # of the additional queries needed.
  #
  # CALL IT LIKE THIS:
  # viewer.codespaces.visible_to_workbench_cloud_environments(viewer)
  #
  # viewer - The user to scope the codespaces for.
  #
  # Returns an ActiveRelation scope.
  def self.visible_to_workbench_cloud_environments(viewer)
    return none unless viewer.spark_enabled?

    not_deprovisioning.only_workbench_cloud_environments.then do |scope|
      # Ensure we use the cached/resolved RepositoryPolicy so that we don't have to resolve all of these sequentially.
      policy_cache = Codespaces::MultiRepositoryPolicyCache.new(scope)
      where(id: scope.filter { _1.accessible?(repository_policy: policy_cache.get(_1)) }.map(&:id))
    end
  end

  # Public: Prefills Codespace associations for dashboard
  #
  # codespaces - An array of Codespace records
  #
  # Returns nothing.
  def self.prefill_associations_for_dashboard(codespaces)
    GitHub::PrefillAssociations.prefill_associations(codespaces, [:owner, :pull_request, :plan, :repository, :blocking_pending_async_operations])
    Repository.prefill_associations(codespaces.map(&:repository), mirror: false)
  end

  def self.active_installations_for(codespace_ids)
    installation_ids = CodespacesSiteScopedIntegrationInstallation
      .where(codespace_id: codespace_ids)
      .pluck(:site_scoped_integration_installation_id)

    SiteScopedIntegrationInstallation
      .where(id: installation_ids)
      .where("expires_at > ?", Time.now.to_i)
  end

  def self.can_be_deprovisioned_by_user(user)
    self.where(owner: user)
      .where.not(state: :deprovisioning)
      .where("environment_data NOT LIKE '%\"hasUnpushedChanges\": true%'")
      .where("environment_data NOT LIKE '%\"hasUncommittedChanges\": true%'")
  end

  # Internal: an abstract collection, for the sub-resources of a Codespace available for permissions.
  def resources
    Codespace::Resources.new(self)
  end

  def billable_owner
    existing = super
    return existing if existing

    return unless owner

    Codespaces::RepositoryPolicy.async_with_prefill(owner, repository).sync.billable_owner
  end

  # Is the codespace accessible?
  #
  # A codespace could be inaccessible if it is unbillable or the underlying
  # repository is unreadable.
  def accessible?(repository_policy: nil)
    # if the codespace owner is nil, they may have been deleted, and it is not accessible
    return false if owner.nil?
    # If the current billable owner is nil, the codespace is unbillable
    return false if billable_owner.nil?

    repository_policy ||= Codespaces::RepositoryPolicy.async_with_prefill(owner, repository, pull_request: pull_request_with_fallback).sync

    # The user can always bill to themselves
    billable = billable_owner == owner || billable_owner == repository_policy.billable_owner
    return false unless billable

    repository_policy.can_attempt_start?
  end

  def pull_request_with_fallback
    with_database_error_fallback(fallback: nil) do
      pull_request
    end
  end

  # TODO: remove this once all codespaces have been backfilled
  def last_used_at
    super || created_at
  end

  def retention_period
    return unless retention_period_minutes

    ActiveSupport::Duration.build(T.must(retention_period_minutes) * 60)
  end

  # Public: update the records `last_used_at` timestamp. Makes
  # sure we're connected to a 'write' connection since we sometimes
  # update this during a GET request.
  def mark_used!
    ActiveRecord::Base.connected_to(role: :writing) do
      touch(:last_used_at)
    end
  end

  # Sends audit log event when user connects to codespace
  # we should send this event every time the user connects even if the codespace is already started
  def instrument_connect
    instrument :connect
  end

  def to_param
    name
  end

  def branch
    unless pinned_to_commit?
      pull_request_with_fallback&.head_ref_name || ref
    end
  end

  def pinned_to_commit?
    return false if !GitRPC::Util.valid_oid?(ref)
    return true if ref == oid && commit.present?
    return false if commit.nil?

    commit.oid.start_with?(ref)
  end

  def commit
    @commit ||= T.cast(repository, T.nilable(Repository))&.commits.find(oid) # rubocop:todo GitHub/AvoidCast
  rescue GitRPC::ObjectMissing
    nil
  end

  def moniker
    repo = repository
    return unless persisted? && repo

    if pull_request
      T.must(pull_request).permalink
    elsif pinned_to_commit?
      commit.permalink
    elsif ref != T.cast(repo, Repository).default_branch # rubocop:todo GitHub/AvoidCast
      "#{repo.permalink}/tree/#{ref}"
    else
      repo.permalink
    end
  end

  def create_type
    repo = repository
    return unless persisted? && repo

    if pull_request
      "pull_request"
    elsif pinned_to_commit?
      "commit"
    elsif ref != T.cast(repo, Repository).default_branch # rubocop:todo GitHub/AvoidCast
      "branch"
    else
      "default"
    end
  end

  def permit?(actor, _action)
    return false if actor.nil?
    return false if owner != actor

    # Always include all cloudspaces in this check if they were able to create them in the first place.
    # We'll exclude them or forbid access when needed.
    T.unsafe(actor&.codespaces).visible_to(actor, include_all_cloudspaces: true).exists?(id:)
  end

  def async_permit?(actor, action)
    Promise.resolve(permit?(actor, action))
  end

  def ref_for_display
    Git::Ref.value_for_display(ref) if ref
  end

  def stuck_provisioning?
    return false unless created_at.present?
    (pending? || provisioning?) && T.must(created_at) < STUCK_STATE_MINUTES.ago
  end

  def never_available?
    creation_failed? || environment_data.state == Codespaces::Vscs::State::PROVISIONING
  end

  def creation_failed?
    environment_data.nil? || environment_data.state == Codespaces::Vscs::State::FAILED
  end

  def deprovision!(reason: nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      deprovisioning!
    end

    CodespacesDeleteJob.enqueue_once_per_interval(
      kwargs: { codespace: self, reason: reason }.compact,
      run_at_beginning_of_interval: true,
      interval: 1.hour,
      unique_id: id
    )
  end

  def suspend!(user = nil, ignore_deleted: false)
    Codespaces::SuspendEnvironment.call(self, user: user, ignore_deleted: ignore_deleted)
  end

  def suspended?
    environment_data&.suspended?
  end

  def suspendable?
    guid && environment_data&.suspendable?
  end

  def deletable?(actor)
    !pending? && !provisioning? ||
      stuck_provisioning? ||
      owner == actor
  end

  def soft_deletable?
    guid? && (codespace? || workbench_cloud_environment? || (workspace_editor_cloud_environment? && WorkspaceEditor::Cloudspaces::Public.soft_deletable_global_setting))
  end

  def soft_delete(reason = Codespace.deletion_reasons[:user_requested])
    return false unless deprovisioning?

    reason_flag = "codespaces_pause_deletions_#{reason}".to_sym
    if FeatureFlag.vexi.enabled_or_raise?(reason_flag, owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub.logger.info(
        "Codespaces Soft Delete Paused",
        "gh.codespaces.codespace_id" => id,
        "gh.codespaces.codespace_guid" => guid,
        "gh.codespaces.deletion_reason" => reason,
        "code.namespace" => "Codespace",
        "code.function" => "soft_delete",
      )
      return false
    end

    if update(deleted_at: Time.zone.now, deletion_reason: reason, state: "deprovisioned")
      GlobalInstrumenter.instrument("codespaces.soft_deleted", codespace: self, reason: reason)
      instrument :soft_deleted, { reason: reason }
      instrument :destroy
      notify_socket_subscribers if owner.present? # Requires an owner
      true
    end
  end

  def reprovision!
    return if provisioning?

    provisioning!
    CodespacesRestoreJob.perform_later(codespace: self)
  end

  def deleted?
    deleted_at.present?
  end

  def restorable?
    (deleted? && deprovisioned?) && !never_available?
  end

  def codespace?
    copilot_workspace_id.blank? && !workbench_cloud_environment?
  end

  def copilot_workspace?
    copilot_workspace_id.present? && !workspace_editor_cloud_environment? && !ephemeral_cloud_environment?
  end

  def workspace_editor_cloud_environment?
    copilot_workspace_id == WorkspaceEditor::Cloudspace::COPILOT_WORKSPACE_ID
  end

  def ephemeral_cloud_environment?
    copilot_workspace_id == EPHEMERAL_CLOUDSPACE_ID
  end

  def workbench_cloud_environment?
    spark_workbench_id.present?
  end

  def export_branch_name
    EXPORT_BRANCH_PREFIX + name
  end

  # Exports codespace to a branch. See packages/codespaces/app/commands/codespaces/export.rb for more
  # info.
  def export!(encrypted_github_token, key_version: nil, actor: nil, new_repository_origin: nil)
    ensure_no_blocking_pending_async_operation!
    exporting! && CodespacesExportJob.perform_later(codespace: self, encrypted_token: encrypted_github_token, key_version: key_version, actor: actor, new_repository_origin: new_repository_origin)
  end

  def exporting!
    return false unless provisioned? && repository

    touch(:last_export_start_at)
  end

  def exported!
    return false unless provisioned? && exporting?

    touch(:last_export_end_at)
  end

  def exporting?
    return false unless last_export_start_at
    return true if last_export_start_at && !last_export_end_at

    T.must(last_export_start_at) > last_export_end_at
  end

  def exported?
    return false unless last_export_start_at && last_export_end_at

    T.must(last_export_end_at) > last_export_start_at
  end

  def export_branch_exists?
    return false unless export_branch

    !!export_branch.exist?
  end

  def stuck_exporting?
    return false unless last_export_start_at

    exporting? && T.must(last_export_start_at) < STUCK_STATE_MINUTES.ago
  end

  def fresh_export_exists?
    return false unless last_export_end_at
    return true unless last_used_at

    T.must(last_export_end_at) > last_used_at && export_branch_exists?
  end

  def export_state
    if exporting? && !stuck_exporting?
      EXPORT_STATE_IN_PROGRESS
    elsif stuck_exporting?
      EXPORT_STATE_FAILED
    elsif export_branch_exists?
      EXPORT_STATE_SUCCEEDED
    else
      EXPORT_STATE_NO_EXPORT_EXISTS
    end
  end

  def export_sha
    export_branch&.sha
  end

  def target_for_conditional_access
    billable_owner
  end

  # Determines the target for for conditional access for multiple Codespace instances
  #
  # codespaces - an enumerable of Codespace
  #
  # returns Hash[Codespace] => target for conditional access
  def self.multiple_target_for_conditional_access(codespaces)
    ConditionalAccess::Filter.ensure_with_class(codespaces, Codespace)
    codespaces.each_with_object({}) { |v, h| h[v] = v.target_for_conditional_access }
  end

  # Delete the export branch if it exists so we go back to the first state
  def delete_export_branch
    ActiveRecord::Base.connected_to(role: :writing) do
      export_branch&.delete(owner)
    end
  end

  def web_portal_url
    "#{vscs_target_config[:web_portal_url_format] % { name: name, second_level_domain: GitHub.codespaces_web_portal_second_level_domain }}"
  end

  def vscode_url
    "vscode://github.codespaces/connect?name=#{EscapeUtils.escape_uri_component(name)}&windowId=_blank"
  end

  def vscode_insiders_url
    "vscode-insiders://github.codespaces/connect?name=#{EscapeUtils.escape_uri_component(name)}&windowId=_blank"
  end

  def jetbrains_url
    "jetbrains-gateway://connect#type=codespaces&codespaceName=#{EscapeUtils.escape_uri_component(name)}"
  end

  def environment_data=(new_data)
    super(new_data).tap do
      self.environment_data_updated_at = Time.current if environment_data_changed?
    end
  end

  def environment_data
    Codespaces::BackfillEnvironmentDataJob.perform_later(codespace: self) if persisted? && read_attribute(:environment_data).blank?
    super
  end

  def display_branch
    current_branch || current_commit || ref
  end

  def vscs_target_config
    Codespaces::Vscs.config_for_target(vscs_target)
  end

  def commits_diverged?
    commits_ahead || commits_behind
  end

  delegate :available?, :current_branch, :current_commit, :commits_ahead,
    :commits_behind, :has_uncommitted_changes?, :has_unpushed_changes?,
    :auto_push?, :allowed_port_privacy_settings, :user_controlled_failure_reason, :using_copilot_workspace_config,
    to: :environment_data, allow_nil: true

  def sku
    Codespaces::Skus.sku_by_name(sku_name) if sku_name
  end

  def track_pr_source!
    return if pull_request.blank?

    PullRequestSource.retry_on_find_or_create_error do
      T.must(pull_request).pull_request_sources.where(source: :codespace).first ||
        T.must(pull_request).pull_request_sources.where(source: :codespace).create
    end
  end

  def consuming_compute?
    environment_data&.consuming_compute?
  end

  def already_started?
    environment_data&.already_started?
  end

  def merge_environment_data!(new_data)
    table_name = Arel.sql(self.class.table_name)
    json = JSON.generate(new_data)
    affected_rows = self.class.connection.update(Arel.sql(<<~SQL, id: id, json: json, table_name: table_name))
      UPDATE `:table_name`
      SET `environment_data` = JSON_MERGE_PATCH(IFNULL(`environment_data`, '{}'), :json),
          `environment_data_updated_at` = CURRENT_TIMESTAMP
      WHERE `id` = :id
    SQL
    unless affected_rows == 1
      raise ActiveRecord::RecordNotFound, "Failed to merge environment data for Codespace with id #{id}"
    end

    # Update the cache but don't reload the whole object since it'd reload the
    # owner object which may have in-memory state (e.g., oauth_access).
    self.environment_data = Codespace.find(T.must(id)).environment_data
  end

  def spammy?
    Codespaces::Policy.codespace_user_spammy?(self)
  end

  # The codespace's display name if one is set or its name if not.
  def safe_display_name
    display_name || name
  end

  def ensure_no_blocking_pending_async_operation!
    Codespaces::AsyncOperation.ensure_no_blocking_pending!(self)
  end

  def blocking_operation?
    blocking_operation.present?
  end

  def blocking_operation_disabled_text
    blocking_operation&.disabled_text || ""
  end

  def notify_socket_subscribers
    return unless repository && owner

    channel = GitHub::WebSocket::Channels.repository_codespaces(repository, owner)
    GitHub::WebSocket.notify_repository_codespaces_channel(repository, channel)
  end

  def auto_deletion_soon?
    return false if keep?

    retention_expiry = retention_expires_at
    return false if retention_expiry.nil?
    return true if retention_expiry <= 24.hours.from_now
    return false if retention_period_minutes.nil?

    # If the retention period has < 25% remaining we'll consider it "soon"
    retention_expiry <= (T.must(retention_period_minutes) * 0.25).minutes.from_now
  end

  def from_codespace_template?
    template_repository_id.present?
  end

  def unpublished?
    #  An unpublished codespace is one that was created from a codespace template and has not yet been published.
    repository_id == template_repository_id
  end

  def published?
    !unpublished?
  end

  def template
    return @template if defined?(@template)
    @template = template_repository ? Codespaces::Template.for_repository(template_repository) : nil
  end

  def requires_git_reinit?
    unpublished? && (!template || template[:slug] != :blank)
  end

  def dev_container
    return @dev_container if defined?(@dev_container)

    @dev_container = Codespaces::DevContainer.new(repository:, oid:, filepath: devcontainer_path)
  end

  def region
    Codespaces::Locations::Region.find(location)
  end

  def service_stamp
    Codespaces::VscsServiceStamp.find(region:, vscs_target:)
  end

  private

  memoize def blocking_operation
    blocking_pending_async_operations.first
  end

  def export_branch
    return nil unless repository

    with_database_error_fallback do
      T.cast(repository, Repository).heads.find(export_branch_name) # rubocop:todo GitHub/AvoidCast
    end
  end

  def destroy_requires_deprovisioning
    # Prevent destroy from being called on records that are not in the
    # `deprovisioning` state. This makes us either either:
    # 1. Call `record.deprovision!` (safest/most desirable).
    # 2. Call `record.deprovisioning! && record.destroy!` if we need other
    #    `on: :destroy` callbacks to run.
    # 3. Call `record.delete` if we just need to nuke the record from the
    #    database. Dangerous because this bypasses validations and callbacks.
    throw(:abort) unless deprovisioning? || deprovisioned?
  end

  def instrument_creation
    GlobalInstrumenter.instrument("codespaces.created",
      codespace: self,
      actor: self.owner,
      billable_owner_in_dunning_cycle: self.billable_owner.dunning?,
      billable_owner: self.billable_owner)
    instrument :create
  end

  def instrument_destroy
    GlobalInstrumenter.instrument("codespaces.destroyed", codespace: self)
  end

  def instrument_repository_changed
    GlobalInstrumenter.instrument(Codespaces::Events::CODESPACE_REPOSITORY_CHANGED, codespace: self)
  end

  def instrument_pull_request_updated
    type = pull_request ? :ATTACHED_TO_PULL_REQUEST : :DETACHED_FROM_PULL_REQUEST
    Codespaces::Events.interaction(codespace: self, type: type)
  end

  def generate_names
    self.display_name = display_name.presence || Codespaces::GenerateDisplayName.call
    generate_name_from_display_name
  end

  def generate_name_from_display_name(attempt: 1)
    return if name.present? # don't override a preset name
    return unless repository && owner # don't bother if we're not in a valid state

    raise ArgumentError, "Max attempts exceeded" if attempt > MAX_NAME_GENERATION_ATTEMPTS
    raise ArgumentError, "Display name is missing" if self.display_name.nil?
    candidate = Codespaces::GenerateName.call(
      owner: owner,
      display_name: display_name
    )

    return generate_name_from_display_name(attempt: attempt + 1) if Codespace.include_deleted.where(name: candidate).exists?
    self.name = candidate
  end

  def set_initial_last_used_at
    self.last_used_at ||= Time.current
  end

  def set_codespace_billing_entry
    return if billing_entry&.persisted?

    self.build_billing_entry \
      billable_owner: billable_owner,
      codespace_owner: owner,
      codespace_guid: guid,
      codespace_plan_name: plan&.name,
      codespace_created_at: created_at,
      repository: repository,
      copilot_workspace_id: copilot_workspace_id,
      spark_workbench_id: spark_workbench_id
  end

  def ensure_repository_id
    return if deprovisioning?
    return if repository_id.present?

    errors.add(:state, "must have a `repository_id`")
  end

  def ensure_valid_state_for_guid
    # don't validate guid when we are deprovisioning...
    return if deprovisioning?
    if guid?
      valid_state = state == "provisioned" || state == "deprovisioned"
      errors.add(:state, "must be 'provisioned' or 'deprovisioned' for codespace with a guid") unless valid_state
    else
      valid_state = %w(pending provisioning failed).include?(state)
      errors.add(:state, "must not be '#{state}' without a guid") unless valid_state
    end
  end

  def valid_environment_data
    return if deprovisioning? || deprovisioned?

    # Using `read_attribute` to avoid calling the accessor which, if blank,
    # will now try to run a background job to backfill the environment data.
    # Originally calling this with a new codespace on save would cause the
    # accessor to try to schedule the background job with a not-yet-persisted
    # model which would blow up. I added a `persisted?` check there to be safe
    # but either way this should also be slightly more performant as we don't
    # have to try to deserialize the JSON string into a Codespaces::Environment
    # object when we don't need to. We also only want to trigger backfills when
    # explicitly accessing `environment_data` not whenever we validate a
    # codespace.
    return if read_attribute(:environment_data).blank? || !guid

    if environment_data.id && environment_data.id != guid
      errors.add(:environment_data, :invalid, message: "Environment data id must match codespace guid")
    end
  end

  def event_prefix
    "codespaces"
  end

  def valid_local_target_url
    unless Codespaces::Vscs.valid_local_target_url?(repository: repository, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
      errors.add(:vscs_target_url, "must be a valid local target URL")
    end
  end

  def event_payload
    # Note that if repository, billable owner and/or owner are nil they were most likely deleted.
    {
      codespace_id: id,
      location: location,
      name: name,
      oid: oid,
      org: billable_owner&.organization? ? billable_owner : nil, # Needs a org_id to appear in the organization's audit logs
      owner: owner&.display_login,
      owner_id: owner&.id,
      pull_request_id: pull_request_with_fallback&.id,
      ref: ref,
      repo: repository,
      sku_name: sku_name,
      machine_type: sku&.display_name,
      user_id: owner&.id, # Needs a user_id or actor_id to appear in the user's audit logs.
      user: owner&.display_login,
      devcontainer_path: devcontainer_path,
    }
  end
end
