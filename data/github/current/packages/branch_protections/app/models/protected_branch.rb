# typed: true
# frozen_string_literal: true

# Public: Protected Branches.
#
# The existence of a protected branch entry for a branch marks the branch as
# "protected". All other branches are considered "unprotected" by default.
#
# If a branch is protected:
# * By default, the branch may only be fast-forwarded
# * By default, the branch may not be deleted
#
# See
#   https://github.com/github/github/settings/branches/master
#
class ProtectedBranch < ApplicationRecord::Repositories
  include GitHub::Validations
  include GitHub::Relay::GlobalIdentification

  include Ability::Subject
  include Ability::Membership

  include Instrumentation::Model

  include ProtectedBranch::PermissionsDependency

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::ProtectedBranch

  # Maximum number of restricted actors that can be specified for a protected branch.
  MAX_AUTHORIZED_ACTORS = 100

  # Maximum number of bytes in a protected branch title
  TITLE_BYTESIZE_LIMIT = 1024

  # Minimum value for the number of required approving reviews
  # A 0 reviewer count enables customers to block direct pushes and require PRs without
  # needing reviewers
  MINIMUM_REQUIRED_APPROVING_REVIEW_COUNT = 0

  # Default value for the number of required approving reviews
  DEFAULT_REQUIRED_APPROVING_REVIEW_COUNT = 1

  # Maximum value for the number of required approving reviews
  MAX_REQUIRED_APPROVING_REVIEW_COUNT = 255

  # Above this number we'll no longer count how many branches a BP rule applies to
  MAX_BRANCHES_TO_CALCULATE_MATCHES = 18000

  # Above this number we'll no longer count how many branches a wilcard BP rule applies to
  MAX_BRANCHES_TO_CALCULATE_WILDCARD_MATCHES = 10000

  # Internal: Raised when trying to add a restricted actor when MAX_AUTHORIZED_ACTORS
  # has already been reached.
  class TooManyPermittedActors < StandardError ; end

  # Internal: Authorized actors are only allowed on org owned repos.
  class OnlyOrgsHaveAuthorizedActors < StandardError ; end

  LEVELS = {
    off: 0,
    non_admins: 1,
    everyone: 2,
  }.with_indifferent_access.freeze

  enum :required_status_checks_enforcement_level, LEVELS, prefix: true
  enum :pull_request_reviews_enforcement_level, LEVELS, prefix: true
  enum :signature_requirement_enforcement_level, LEVELS, prefix: true
  enum :block_force_pushes_enforcement_level, LEVELS, prefix: true
  enum :block_deletions_enforcement_level, LEVELS, prefix: true
  enum :merge_queue_enforcement_level, LEVELS, prefix: true
  enum :lock_branch_enforcement_level, LEVELS, prefix: true

  # part of step 2 in https://github.com/github/ce-oss-happiness/issues/69
  # replacing block_force_pushes_enforcement_level
  enum :allow_force_pushes_enforcement_level, LEVELS, prefix: true
  # replacing block_deletions_enforcement_level
  enum :allow_deletions_enforcement_level, LEVELS, prefix: true

  enum :linear_history_requirement_enforcement_level, LEVELS, prefix: true

  enum :required_deployments_enforcement_level, LEVELS, prefix: true

  enum :required_review_thread_resolution_enforcement_level, LEVELS, prefix: true

  # This was originally used for migrating ProtectedBranch to RuleConfig
  # The code that uses this is now removed, but we keep this enum here because
  # the column still exists in the DB
  MIGRATION_STAGES = {
    unmigrated: 0,
    migrated_without_associations: 1,
    migrated_with_allowances: 2
  }.with_indifferent_access.freeze
  enum :migration_stage, MIGRATION_STAGES

  validates :repository_id, presence: true
  validates :name, presence: true, uniqueness: { scope: :repository_id, message: "already protected: %{value}", case_sensitive: true }
  validates :creator_id, presence: true
  validates :name, bytesize: { maximum: TITLE_BYTESIZE_LIMIT }
  validate :creator_must_be_user
  validate :rule_is_valid

  validates :required_status_checks_enforcement_level, presence: true
  validates :pull_request_reviews_enforcement_level, presence: true
  validates :signature_requirement_enforcement_level, presence: true
  validates :linear_history_requirement_enforcement_level, presence: true
  validates :block_force_pushes_enforcement_level, presence: true
  validates :block_deletions_enforcement_level, presence: true
  validates :merge_queue_enforcement_level, presence: true
  validate :ensure_consistent_merge_strategies
  validate :ensure_consistent_merge_strategy_for_merge_queue
  validates :required_deployments_enforcement_level, presence: true
  validates :required_review_thread_resolution_enforcement_level, presence: true
  validates :lock_branch_enforcement_level, presence: true
  validate :ensure_qualified_branch_name_for_merge_queue
  validate :prevent_branch_name_change_for_merge_queue, on: :update
  validate :prevent_required_deployments_for_merge_queue
  validate :ensure_no_duplicate_merge_queue
  validates_inclusion_of :create_protected, in: [true, false]

  validate :ensure_branch_protection_enabled

  validates_numericality_of :required_approving_review_count, {
    greater_than_or_equal_to: MINIMUM_REQUIRED_APPROVING_REVIEW_COUNT,
    less_than_or_equal_to: MAX_REQUIRED_APPROVING_REVIEW_COUNT,
    only_integer: true,
  }

  has_many :required_status_checks, -> { order("id") }, inverse_of: :protected_branch
  destroy_dependents_in_background :required_status_checks

  has_many :required_deployments
  destroy_dependents_in_background :required_deployments

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  destroy_in_background_with :repository
  belongs_to :creator, class_name: :User
  has_many :review_dismissal_allowances
  has_one :merge_queue, dependent: :destroy

  has_many :branch_actor_allowances

  after_commit :clear_saved_changes

  before_destroy :generate_webhook_payload
  after_save :update_abilities_and_instrument_changes
  after_create_commit :instrument_create
  after_update_commit :instrument_update
  after_update_commit :enqueue_auto_merge_job_if_enabled
  after_commit :synchronize_search_index
  after_destroy_commit :clear_app_permissions
  after_destroy_commit :instrument_destroy
  after_destroy_commit :queue_webhook_delivery

  after_commit :sync_merge_queue, on: [:create, :update]

  attr_accessor :merge_queue_settings_hash, :callback_args

  # derive values for allow_*_enforcement_level from block_*_enforcement_level to prepare for column renames
  before_validation :derive_force_pushes_enforcement_level, if: :will_save_change_to_block_force_pushes_enforcement_level?
  before_validation :derive_deletions_enforcement_level, if: :will_save_change_to_block_deletions_enforcement_level?

  # turn off create_protected unless push protections are enabled
  before_validation :sync_create_protected

  extend Scientist

  # Returns the protection for the given branch name in the given repository.
  def self.for_repository_with_branch_name(repository, branch_name)
    Platform::Loaders::BranchProtectionRule::ByBranchName.load(repository, branch_name).sync
  end

  # Returns a mapping of branch names to protections for the given repository and branch names.
  def self.for_repository_with_branch_names(repository, branch_names)
    protected_branches = Platform::Loaders::BranchProtectionRule::ByBranchName.load_many(repository, branch_names).sync
    branch_names.zip(protected_branches).to_h
  end

  def clear_app_permissions
    entry_point = @callback_args && @callback_args[:entry_point] || :unknown_protected_branch_clear_app_permissions
    Permissions::QueryRouter.delete_app_permissions_on_subject(self, entry_point: entry_point)
  end

  def resources
    ProtectedBranch::Resources.new(self)
  end

  # Generates a set of rules that represent this ProtectedBranch
  # Called exclusively by ProtectedBranchRuleProvider
  def generate_rules(provider)
    policies = []
    policies << RepositoryRuleConfiguration.create_provider_rule(
      provider: provider,
      matching_ref_names: [],
      source: self,
      rule_type: "required_linear_history",
    ) if required_linear_history_enabled?

    if merge_queue_enabled?
      lazy_merge_queue = MergeQueues.lazy_load(repository_id, name)
      policies << RepositoryRuleConfiguration.create_provider_rule(
        provider: provider,
        matching_ref_names: [],
        source: self,
        rule_type: "merge_queue",
        lazy_parameters: {
          grouping_strategy: -> { lazy_merge_queue.resolve(&:merging_strategy) },
          merge_method: -> { lazy_merge_queue.resolve(&:merge_method).upcase },
          min_entries_to_merge: -> { lazy_merge_queue.resolve(&:min_entries_to_merge) },
          max_entries_to_merge: -> { lazy_merge_queue.resolve(&:max_entries_to_merge) },
          min_entries_to_merge_wait_minutes: -> { lazy_merge_queue.resolve(&:min_entries_to_merge_wait_minutes) },
          max_entries_to_build: -> { lazy_merge_queue.resolve(&:max_entries_to_build) },
          check_run_retries_limit: -> { lazy_merge_queue.resolve(&:check_run_retries_limit) },
          actor_controlled_merging: -> { lazy_merge_queue.resolve(&:actor_controlled_merging?) },
          check_response_timeout_minutes: -> do
            [lazy_merge_queue.resolve(&:check_response_timeout_minutes), 1].max
          end
        }
      )
    end

    policies << RepositoryRuleConfiguration.create_provider_rule(
      provider: provider,
      matching_ref_names: [],
      source: self,
      rule_type: "required_review_thread_resolution",
    ) if required_review_thread_resolution_enabled?

    policies << RepositoryRuleConfiguration.create_provider_rule(
      provider: provider,
      matching_ref_names: [],
      source: self,
      rule_type: "required_deployments",
      lazy_parameters: {
        required_deployment_environments: lambda { required_deployments.map(&:environment) }
      }
    ) if required_deployments_enabled?

    policies << RepositoryRuleConfiguration.create_provider_rule(
      provider: provider,
      matching_ref_names: [],
      source: self,
      rule_type: "required_signatures",
    ) if required_signatures_enabled?

    pr_policy = pull_request_policy
    policies << pr_policy if pr_policy

    status_checks_policy = required_status_checks_policy
    policies << status_checks_policy if status_checks_policy

    policies << RepositoryRuleConfiguration.create_provider_rule(
      provider: provider,
      matching_ref_names: [],
      source: self,
      rule_type: "non_fast_forward",
      lazy_parameters: {
        actor_allowances: lambda { branch_actor_allowances_for_policy(:force_push).all }
      }
    ) if block_force_pushes_enabled?

    policies << RepositoryRuleConfiguration.create_provider_rule(
      provider: provider,
      matching_ref_names: [],
      source: self,
      rule_type: "deletion"
    ) if block_deletions_enabled?

    policies << RepositoryRuleConfiguration.create_provider_rule(
      provider: provider,
      matching_ref_names: [],
      source: self,
      rule_type: "lock_branch",
      parameters: {
        lock_allows_fetch_and_merge: lock_allows_fetch_and_merge?
      }
    ) if lock_branch_enabled?

    policies << RepositoryRuleConfiguration.create_provider_rule(
      provider: provider,
      matching_ref_names: [],
      source: self,
      rule_type: "authorization"
    ) if has_authorized_actors?

    policies
  end

  def pull_request_policy
    RepositoryRuleConfiguration.create_provider_rule(
      provider: T.must(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "protected_branch" }),
      matching_ref_names: [],
      source: self,
      rule_type: "pull_request",
      parameters: {
        required_approving_review_count: required_approving_review_count,
        require_code_owner_review: require_code_owner_review?,
        dismiss_stale_reviews_on_push: dismiss_stale_reviews_on_push?,
        authorized_dismissal_actors_only: authorized_dismissal_actors_only?
      },
      lazy_parameters: {
        actor_allowances: lambda { branch_actor_allowances_for_policy(:pull_request).all },
        ignore_approvals_from_contributors: lambda { ignore_approvals_from_contributors? },
        require_last_push_approval: lambda { require_last_push_approval? },
        dismissal_allowances: lambda { review_dismissal_allowances.all }
      }
    ) if pull_request_required?
  end

  def required_status_checks_policy
    RepositoryRuleConfiguration.create_provider_rule(
      provider: T.must(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "protected_branch" }),
      matching_ref_names: [],
      source: self,
      rule_type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: strict_required_status_checks_policy?
      },
      lazy_parameters: {
        required_status_checks: lambda { required_status_checks.all },
        async_required_status_checks: lambda { async_required_status_checks },
      }
    ) if required_status_checks_enabled?
  end

  # Public: Replace protected status children with a list of new contexts.
  #
  # contexts - Array of String context names
  #
  # Returns nothing.
  def replace_status_contexts(contexts)
    preserve_status_checks_contexts
    contexts = Array(contexts)

    transaction do
      diff = diff_status_contexts(contexts)
      destroy_required_status_checks(diff.destroy)
      create_required_status_checks(diff.create)
    end
  end

  # Public: Replace existing required status checks with new values.
  #
  # statuses - Array of Hashes, with the keys :context, :integration, and
  #            :source
  #
  # Returns nothing
  def replace_statuses(statuses)
    preserve_status_checks_contexts

    checks_by_context = self.required_status_checks.index_by(&:context)
    new_contexts = statuses.map { |status| status[:context] }
    redundant_contexts = checks_by_context.keys - new_contexts

    transaction do
      statuses.each do |status|
        context = status[:context]
        source = status.fetch(:source, :app)

        integration = if source == :any
          nil
        elsif status[:integration].present?
          status[:integration]
        elsif checks_by_context.has_key?(context)
          checks_by_context[context].integration
        else
          possible_required_status_contexts_and_integrations.fetch(context, []).first
        end

        if checks_by_context.has_key?(context)
          checks_by_context[context].update!(integration: integration)
        else
          required_status_checks.create!(context: context, integration: integration)
        end
      end

      destroy_required_status_checks(redundant_contexts)
    end
  end

  CONTAINS_WILDCARD = /\*|\?|\\|\[/.freeze

  def wildcard_rule?
    name.match?(CONTAINS_WILDCARD)
  end

  def matches_qualified_ref_name?(qualified_ref_name)
    File.fnmatch?(qualified_name, qualified_ref_name, File::FNM_PATHNAME)
  end

  def matches?(branch_name)
    File.fnmatch?(name, branch_name, File::FNM_PATHNAME)
  end

  # Public: Create associated RequiredStatusChecks for the given contexts.
  #
  # contexts - Array of String Status context names
  #
  # Returns nothing.
  def create_required_status_checks(contexts)
    integration_lookup = possible_required_status_contexts_and_integrations

    contexts.each do |c|
      integration = integration_lookup.fetch(c, []).first
      self.required_status_checks.create!(context: c, integration: integration)
    end
  end

  # Public: Destroy associated RequiredStatusChecks matching the given
  # contexts.
  #
  # contexts - Array of String Status context names
  #
  # Returns an array of the destroyed status checks.
  def destroy_required_status_checks(contexts)
    checks_by_context = self.required_status_checks.index_by(&:context)
    self.required_status_checks.destroy(checks_by_context.values_at(*contexts).compact)
  end

  # Public: Update required status check settings.
  #
  # strict         - Optional Boolean specifying whether the branch must
  #                  be up to date with the base branch to pass
  #                  required status checks.
  # contexts       - Optional Array containing a list of context names
  #                  to be used for required status checks.
  # checks         - Optional Array containing Hashes with `:context` and
  #                  `:integration` keys to be used for required status
  #                  checks. Will take prescedence over `contexts` if both are
  #                  given.
  # include_admins - Optional Boolean specifying whether admin users are
  #                  included in required status checks.
  def update_required_status_checks(include_admins: nil, strict: nil, contexts: nil, checks: nil)
    unless include_admins.nil?
      self.required_status_checks_enforcement_level = include_admins ? LEVELS[:everyone] : LEVELS[:non_admins]
      self.admin_enforced = include_admins ? true : false
    end
    self.required_status_checks_enforcement_level = LEVELS[:non_admins] unless required_status_checks_enabled?
    self.strict_required_status_checks_policy = strict unless strict.nil?

    if !checks.nil?
      self.replace_statuses(checks)
    elsif !contexts.nil?
      self.replace_status_contexts(contexts)
    end
  end

  # Public: Clear required status check settings.
  def clear_required_status_checks
    preserve_status_checks_contexts
    self.strict_required_status_checks_policy = true
    self.required_status_checks_enforcement_level = disabled_enforcement_level
    self.required_status_checks.destroy_all
  end

  # Public: Enable pull request review enforcement.
  #
  # dismissal_restrictions - Optional hash specifying users and teams that have
  #                  dismissal power
  # dismiss_stale_reviews - Optional Boolean specifying weather to turn on dismiss
  #                  stale reviews or not
  # require_code_owner_reviews - Optional Boolean specifying weather to turn on requiring
  #                  code owners reviews or not
  # require_last_push_approval - Optional Boolean specifying weather to turn on requiring
  #                  and approval from someone other than the last pusher
  def enable_required_pull_request_reviews(
    dismissal_restrictions: nil,
    dismiss_stale_reviews: nil,
    require_code_owner_reviews: nil,
    required_approving_review_count: nil,
    require_last_push_approval: nil,
    bypass_pull_request_allowances: nil
  )

    unless pull_request_reviews_enabled?
      self.pull_request_reviews_enforcement_level = enabled_enforcement_level(non_admins_possible: true)
    end

    unless dismiss_stale_reviews.nil?
      self.dismiss_stale_reviews_on_push = dismiss_stale_reviews
    end

    unless require_code_owner_reviews.nil?
      self.require_code_owner_review = require_code_owner_reviews
    end

    unless required_approving_review_count.nil?
      self.required_approving_review_count = required_approving_review_count
    end

    if !require_last_push_approval.nil?
      self.require_last_push_approval = require_last_push_approval
    end

    if dismissal_restrictions
      raise OnlyOrgsHaveAuthorizedActors unless repository&.in_organization?

      if dismissal_restrictions.empty?
        clear_dismissal_restrictions
      else
        replace_dismissal_restricted_actors(
          user_ids: User.where(login: dismissal_restrictions["users"]).pluck(:id),
          team_ids: repository&.organization&.teams&.where(slug: dismissal_restrictions["teams"])&.pluck(:id) || [],
          integration_ids: Integration.where(slug: dismissal_restrictions["apps"]).pluck(:id),
        )
      end
    end

    if bypass_pull_request_allowances
      raise OnlyOrgsHaveAuthorizedActors unless repository&.in_organization?

      if bypass_pull_request_allowances.empty?
        clear_branch_actor_allowances(:pull_request)
      else
        replace_branch_actor_allowances(
          :pull_request,
          user_ids: User.where(login: bypass_pull_request_allowances["users"]).pluck(:id),
          team_ids: repository&.organization&.teams&.where(slug: bypass_pull_request_allowances["teams"])&.pluck(:id) || [],
          integration_ids: Integration.where(slug: bypass_pull_request_allowances["apps"]).pluck(:id))
      end
    end
  end

  # Public: Does this protected branch enforce code owner reviews? Always returns
  # false if the feature is not supported by repo's billing plan.
  #
  # Returns a Boolean
  def require_code_owner_review
    return false unless repository&.plan_supports?(:codeowners)

    super
  end
  alias_method :require_code_owner_review?, :require_code_owner_review

  # Public: Clear pull request review enforcement settings
  def clear_required_pull_request_reviews
    self.pull_request_reviews_enforcement_level = disabled_enforcement_level
    self.dismiss_stale_reviews_on_push = false
    self.require_code_owner_review = false
    self.required_approving_review_count = DEFAULT_REQUIRED_APPROVING_REVIEW_COUNT
    self.ignore_approvals_from_contributors = false
    self.require_last_push_approval = false
    clear_dismissal_restrictions
    clear_branch_actor_allowances(:pull_request)
  end

  def clear_dismissal_restrictions
    change_made = review_dismissal_allowances.count > 0
    review_dismissal_allowances.destroy_all
    change_made ||= self.authorized_dismissal_actors_only
    self.authorized_dismissal_actors_only = false
    instrument_dismissal_restricted_actors if change_made
  end

  def clear_branch_actor_allowances(policy)
    allowances = branch_actor_allowances_for_policy(policy)
    change_made = allowances.count > 0
    allowances.destroy_all
    instrument_branch_allowances(policy) if change_made
  end

  def enable_required_signatures
    self.signature_requirement_enforcement_level = enabled_enforcement_level(non_admins_possible: true)
  end

  def clear_required_signatures
    self.signature_requirement_enforcement_level = disabled_enforcement_level
  end

  def enable_required_linear_history
    self.linear_history_requirement_enforcement_level = enabled_enforcement_level(non_admins_possible: true)
  end

  def clear_required_linear_history
    self.linear_history_requirement_enforcement_level = disabled_enforcement_level
  end

  def enable_create_protected
    self.create_protected = true
  end

  def clear_create_protected
    self.create_protected = false
  end

  def enable_merge_queue
    return unless repository&.merge_queue_enabled?

    self.merge_queue_enforcement_level = enabled_enforcement_level(non_admins_possible: true)
  end

  def clear_merge_queue
    self.merge_queue_enforcement_level = disabled_enforcement_level
  end

  # Public: Prevent anyone from force-pushing to branches covered by this rule. This is the default for new
  # ProtectedBranches.
  #
  # Unlike other ProtectedBranch settings, blocked force pushes are everyone or no-one, regardless of the value of
  # `:admin_enforced?`.
  def enable_blocked_force_pushes
    self.block_force_pushes_enforcement_level = enabled_enforcement_level(non_admins_possible: false)
  end

  def enable_lock_branch
    self.lock_branch_enforcement_level = enabled_enforcement_level(non_admins_possible: true)
  end

  def clear_lock_branch
    self.lock_branch_enforcement_level = disabled_enforcement_level
    self.lock_allows_fetch_and_merge = false
  end

  # Public: Allow force pushes to branches covered by this rule.
  def clear_blocked_force_pushes
    self.block_force_pushes_enforcement_level = disabled_enforcement_level
  end

  # Public: Prevent anyone from deleting branches covered by this rule. This is the default for new ProtectedBranches.
  #
  # Unlike other ProtectedBranch settings, blocked deletions are everyone or no-one, regardless of the value of
  # `:admin_enforced?`.
  def enable_blocked_deletions
    self.block_deletions_enforcement_level = enabled_enforcement_level(non_admins_possible: false)
  end

  # Public: Allow branches covered by this rule to be deleted.
  def clear_blocked_deletions
    self.block_deletions_enforcement_level = disabled_enforcement_level
  end

  def enable_required_deployments
    self.required_deployments_enforcement_level = enabled_enforcement_level(non_admins_possible: true)
  end

  def enable_required_review_thread_resolution
    self.required_review_thread_resolution_enforcement_level = enabled_enforcement_level(non_admins_possible: true)
  end

  def clear_required_review_thread_resolution
    self.required_review_thread_resolution_enforcement_level = disabled_enforcement_level
  end

  def clear_required_deployment_environments
    self.required_deployments_enforcement_level = disabled_enforcement_level
    required_deployments.destroy_all
  end

  def replace_required_deployment_environments(environments)
    environments = Array(environments)

    transaction do
      added, removed = diff_environments(environments)
      destroy_required_environments(removed)
      create_required_environments(added)
    end
  end

  def destroy_required_environments(environments)
    deployments_by_environment = self.required_deployments.index_by(&:environment)
    self.required_deployments.destroy(deployments_by_environment.values_at(*environments).compact)
  end

  def create_required_environments(environments)
    environments = environments & possible_required_deployment_environments
    environments.each { |e| self.required_deployments.create!(environment: e, protected_branch: self) }
  end

  # Public: Update push restriction settings.
  #
  # Allows setting or updating the list of users, teams or integrations that are
  # restricted to pushing to the protected branch.
  #
  # Note: Setting users, teams, integrations to empty lists does not disable
  #       push restrictions, but limits pushes to admins only. Use
  #       `clear_restrictions` to disable push restrictions.
  #
  # users        - Optional Array of User login names.
  # teams        - Optional Array of Team slug names.
  # integrations - Optional Array of Integration slug names.
  # entry_point  - Optional identifier for for the call site of this method for tracking purposes.
  def update_restrictions(users: nil, teams: nil, integrations: nil, entry_point: nil)
    user_ids = if users
      User.where(login: users).pluck(:id)
    else
      authorized_user_ids
    end

    team_ids = if teams
      repository&.teams(immediate_only: false)&.where(slug: teams)&.pluck(:id) || []
    else
      authorized_team_ids
    end

    integration_ids = if integrations
      Integration.where(slug: integrations).pluck(:id)
    else
      authorized_integration_ids
    end

    replace_authorized_actors(user_ids: user_ids, team_ids: team_ids, integration_ids: integration_ids, entry_point: entry_point)
  end

  # Public: Clear push restriction settings.
  def clear_restrictions
    self.authorized_actors_only = false
  end

  def add_users_to_restrictions(user_logins, entry_point:)
    present_user_logins = authorized_users.map(&:login_for_api)
    update_restrictions(users: user_logins + present_user_logins, entry_point: entry_point)
  end

  def remove_users_from_restrictions(user_logins, entry_point:)
    present_user_logins = authorized_users.map(&:login_for_api)
    update_restrictions(users: present_user_logins - user_logins, entry_point: entry_point)
  end

  def add_teams_to_restrictions(team_slugs, entry_point:)
    present_team_slugs = authorized_teams.map(&:slug)
    update_restrictions(teams: team_slugs + present_team_slugs, entry_point: entry_point)
  end

  def remove_teams_from_restrictions(team_slugs, entry_point:)
    present_team_slugs = authorized_teams.map(&:slug)
    update_restrictions(teams: present_team_slugs - team_slugs, entry_point: entry_point)
  end

  def add_integrations_to_restrictions(integration_slugs, entry_point:)
    update_restrictions(integrations: integration_slugs + authorized_integration_slugs, entry_point: entry_point)
  end

  def remove_integrations_from_restrictions(integration_slugs, entry_point:)
    update_restrictions(integrations: authorized_integration_slugs - integration_slugs, entry_point: entry_point)
  end

  # Public: Get qualified ref name for branch.
  #
  # Examples
  #   "refs/heads/master"
  #
  # Returns String.
  def qualified_name
    "refs/heads/#{name}"
  end

  def admin_enforced=(value)
    if value
      self.pull_request_reviews_enforcement_level = LEVELS[:everyone] if pull_request_reviews_enabled?
      self.required_status_checks_enforcement_level = LEVELS[:everyone] if required_status_checks_enabled?
      self.signature_requirement_enforcement_level = LEVELS[:everyone] if required_signatures_enabled?
      self.linear_history_requirement_enforcement_level = LEVELS[:everyone] if required_linear_history_enabled?
      self.required_deployments_enforcement_level = LEVELS[:everyone] if required_deployments_enabled?
      self.required_review_thread_resolution_enforcement_level = LEVELS[:everyone] if required_review_thread_resolution_enabled?
      self.merge_queue_enforcement_level = LEVELS[:everyone] if merge_queue_enabled?
      self.lock_branch_enforcement_level = LEVELS[:everyone] if lock_branch_enabled?
    else
      self.pull_request_reviews_enforcement_level = LEVELS[:non_admins] if pull_request_reviews_enabled?
      self.required_status_checks_enforcement_level = LEVELS[:non_admins] if required_status_checks_enabled?
      self.signature_requirement_enforcement_level = LEVELS[:non_admins] if required_signatures_enabled?
      self.linear_history_requirement_enforcement_level = LEVELS[:non_admins] if required_linear_history_enabled?
      self.required_deployments_enforcement_level = LEVELS[:non_admins] if required_deployments_enabled?
      self.required_review_thread_resolution_enforcement_level = LEVELS[:non_admins] if required_review_thread_resolution_enabled?
      self.merge_queue_enforcement_level = LEVELS[:non_admins] if merge_queue_enabled?
      self.lock_branch_enforcement_level = LEVELS[:non_admins] if lock_branch_enabled?
    end
    super
  end

  # Public: Can this actor override required status checks?
  #
  # actor - User/Bot or PublicKey to check for
  #
  # Returns Boolean
  def can_override_status_checks?(actor:)
    return false unless actor

    result = can_override_protection?(enforcement_level: required_status_checks_enforcement_level, actor: actor)
    log_can_override_protection_result(type: "status_checks", enforcement_level: required_status_checks_enforcement_level, actor: actor, result: result)
    result
  end

  # Public: Can this actor override rejected pull request reviews?
  #
  # actor - User/Bot or PublicKey to check for
  #
  # Returns Boolean
  def can_override_review_policy?(actor:)
    return false unless actor
    return true if has_branch_actor_allowance?(:pull_request, actor: actor)

    result = can_override_protection?(enforcement_level: pull_request_reviews_enforcement_level, actor: actor)
    log_can_override_protection_result(type: "pull_request_reviews", enforcement_level: pull_request_reviews_enforcement_level, actor: actor, result: result)
    result
  end

  def can_override_force_push_policy?(actor:)
    return false unless actor
    true if has_branch_actor_allowance?(:force_push, actor: actor)
  end

  def has_branch_actor_allowance?(policy, actor:)
    return true if branch_actor_allowances_for_policy(policy).where(actor_id: actor.id, actor_type: "User").any?

    if actor.is_a?(Bot)
      integration_installations = branch_actor_allowance_integration_installations(policy)
      return false unless integration_installations.any?

      return IntegrationInstallation.where(id: integration_installations.map(&:id))
        .joins(:integration)
        .where({ integrations: { id: T.must(actor.integration).id } })
        .any?
    end

    teams = branch_actor_allowance_teams(policy)
    teams.any? && Team.member_of?(teams.map(&:id), actor.id, immediate_only: false)
  end

  # Public: Can this actor override required signatures?
  #
  # actor - User/Bot or PublicKey to check for.
  #
  # Returns boolean.
  def can_override_required_signatures?(actor:)
    return false unless actor

    result = can_override_protection?(enforcement_level: signature_requirement_enforcement_level, actor: actor)
    log_can_override_protection_result(type: "signatures", enforcement_level: signature_requirement_enforcement_level, actor: actor, result: result)
    result
  end

  def can_override_required_review_thread_resolution?(actor:)
    return false unless actor

    result = can_override_protection?(enforcement_level: required_review_thread_resolution_enforcement_level, actor: actor)
    log_can_override_protection_result(type: "review_thread_resolution", enforcement_level: required_review_thread_resolution_enforcement_level, actor: actor, result: result)
    result
  end

  # Public: Can this actor override blocked merge commits?
  #
  # actor = User/Bot or PublicKey to check for.
  # is_pull_request allows compatibility with the equivalent ref-update rule. Its value doesn't matter, because branch
  # protections don't provide any "bypass only using a PR" setting.
  #
  # Returns boolean.
  def can_override_required_linear_history?(actor:, is_pull_request: false)
    return false unless actor

    result = can_override_protection?(enforcement_level: linear_history_requirement_enforcement_level, actor: actor)
    log_can_override_protection_result(type: "linear_history", enforcement_level: linear_history_requirement_enforcement_level, actor: actor, result: result)
    result
  end

  def required_signatures_enforced_for?(actor:)
    return false unless required_signatures_enabled?
    return true if signature_requirement_enforcement_level == "everyone"

    !can_override_required_signatures?(actor: actor)
  end

  def required_status_checks_enforced_for?(actor:)
    return false unless required_status_checks_enabled?
    return true if required_status_checks_enforcement_level == "everyone"

    !can_override_status_checks?(actor: actor)
  end

  def required_review_policy_enforced_for?(actor:)
    return false unless pull_request_reviews_enabled?

    !can_override_review_policy?(actor: actor)
  end

  def required_linear_history_enforced_for?(actor:)
    return false unless required_linear_history_enabled?
    return true if linear_history_requirement_enforcement_level == "everyone"

    !can_override_required_linear_history?(actor: actor)
  end

  def required_review_thread_resolution_enforced_for?(actor:)
    return false unless required_review_thread_resolution_enabled?
    return true if required_review_thread_resolution_enforcement_level == "everyone"

    !can_override_required_review_thread_resolution?(actor: actor)
  end

  def pull_request_reviews_enabled?
    !pull_request_reviews_enforcement_level_off?
  end

  def required_status_checks_enabled?
    !required_status_checks_enforcement_level_off?
  end

  def required_signatures_enabled?
    !signature_requirement_enforcement_level_off?
  end

  def required_linear_history_enabled?
    !linear_history_requirement_enforcement_level_off?
  end

  def create_protected_enabled?
    create_protected
  end

  def block_force_pushes_enabled?
    !block_force_pushes_enforcement_level_off?
  end

  def lock_branch_enabled?
    !lock_branch_enforcement_level_off?
  end

  def block_deletions_enabled?
    !block_deletions_enforcement_level_off?
  end

  def required_deployments_enabled?
    !required_deployments_enforcement_level_off?
  end

  def required_review_thread_resolution_enabled?
    !required_review_thread_resolution_enforcement_level_off?
  end

  def merge_queue_enabled?
    !merge_queue_enforcement_level_off?
  end

  def admin_enforced?
    admin_enforced ||
      required_status_checks_enforcement_level_everyone? ||
      pull_request_reviews_enforcement_level_everyone? ||
      signature_requirement_enforcement_level_everyone? ||
      linear_history_requirement_enforcement_level_everyone? ||
      required_deployments_enforcement_level_everyone? ||
      required_review_thread_resolution_enforcement_level_everyone? ||
      merge_queue_enforcement_level_everyone? ||
      lock_branch_enforcement_level_everyone?
  end

  # Internal: are PullRequestReviews required for this protected branch?
  def pull_request_reviews_required?
    !pull_request_reviews_enforcement_level_off? && required_approving_review_count > 0
  end

  # Internal: is a PullRequest required for this protected branch?
  def pull_request_required?
    !pull_request_reviews_enforcement_level_off?
  end

  # Public: Return the possible required status contexts for this branch, and
  # the integrations that have been used to create these checks.
  # This includes recent status contexts seen in the repository as well
  # as any existing required status checks.
  #
  # Returns a Hash of Sets of Integrations
  def possible_required_status_contexts_and_integrations
    return [] if (repo = repository).nil?

    @possible_required_status_contexts_and_integrations ||= (
      start = 1.week.ago

      possible_required_status_limit = RequiredStatusCheck::MAX_PER_BRANCH
      if repo.feature_enabled_for_repo_or_owner?(:possible_required_status_limit) && GitHub.flipper[:possible_required_status_limit_value].percentage_of_time_value > 0
        possible_required_status_limit = (possible_required_status_limit * (GitHub.flipper[:possible_required_status_limit_value].percentage_of_time_value / 100)).to_i
      end

      statuses = Statuses.domain.recent_status_contexts_and_integrations(repository_id: repo.id, start: start, limit: possible_required_status_limit)
      checks = CheckRun.recent_check_names_and_integrations(repo:, start: start, limit: possible_required_status_limit)
      existing_requirements = RequiredStatusCheck.pluck_contexts_and_integrations(required_status_checks)

      statuses
        .merge(checks) { |_, set_a, set_b| set_a | set_b }
        .merge(existing_requirements) { |_, set_a, set_b| set_a | set_b }
    )
  end

  def possible_required_deployment_environments
    if repository&.feature_enabled_for_repo_or_owner?(:possible_required_deployments_limit) && GitHub.flipper[:possible_required_deployments_limit_value].percentage_of_time_value > 0
      possible_required_deployments_limit = (1000 * (GitHub.flipper[:possible_required_deployments_limit_value].percentage_of_time_value / 100)).to_i
      @possible_required_deployment_environments ||= repository&.environments&.limit(possible_required_deployments_limit)&.pluck(:name) || []
    else
      @possible_required_deployment_environments ||= repository&.environments&.pluck(:name) || []
    end
  end

  # Public: Does this protected branch have restricted actors specified for review dismissal?
  #
  # Returns Boolean
  def restricted_dismissed_reviews?
    authorized_dismissal_actors_only? && repository&.in_organization?
  end

  # Public: Does this protected branch have restricted actors specified?
  # Personal accounts can never have authorized actors.
  #
  # Returns Boolean
  def has_authorized_actors?
    # The repo can be nil when the repo has been deleted and the protected branch is being deleted
    # In that case, we should let the authorized actors be read and sent in the webhook
    authorized_actors_only? && (repository.nil? || repository&.in_organization?)
  end

  def authorized_actors_only=(value)
    if value
      raise NotImplementedError, "Changing authorized_actors_only to true must be done in replace_authorized_actors."
    end
    preserve_authorized_actor_info

    super(!!value)
  end

  def authorized_dismissal_actors_only=(value)
    if value
      raise NotImplementedError, "Changing authorized_dismissal_actors_only to true must be done in replace_dismissal_restricted_actors."
    end
    preserve_dismissal_restrictions

    super(!!value)
  end

  # Public: Set the restricted users/teams/integrations for this protected branch.
  # Only works on org owned repositories.
  #
  # user_ids        - Optional Array of User ids
  # team_ids        - Optional Array of Team ids
  # integration_ids - Optional Array of Integration ids
  # entry_point     - Optional identifier for for the call site of this method for tracking purposes.
  #
  # Returns nothing
  def replace_authorized_actors(user_ids:, team_ids:, integration_ids: nil, entry_point: nil)
    preserve_authorized_actor_info
    raise OnlyOrgsHaveAuthorizedActors unless repository&.in_organization?

    user_ids ||= []
    team_ids ||= []
    integration_ids ||= []

    num_authorized_actors = user_ids.length + team_ids.length + integration_ids.length
    if num_authorized_actors > MAX_AUTHORIZED_ACTORS
      raise TooManyPermittedActors.new("Only #{MAX_AUTHORIZED_ACTORS} users, teams, and apps can be specified.")
    end

    # Use update_column so `authorized_actors_only=` isn't called.
    update_column(:authorized_actors_only, true) unless has_authorized_actors?

    @callback_args = { entry_point: entry_point }
    clear_authorized_actor_abilities_and_permissions

    if team_ids.any?
      T.must(repository).teams(immediate_only: false).where(id: team_ids).each do |team|
        add_authorized_actor(team)
      end
    end

    if user_ids.any?
      User.where(id: user_ids).each do |user|
        add_authorized_actor(user)
      end
    end

    # Find IntegrationInstallations by integration id scoped by repository
    if integration_ids.any?
      IntegrationInstallation.with_repository(repository).joins(:integration).
        where(integrations: { id: integration_ids }).each do |integration_installation|
          add_authorized_actor(integration_installation)
        end
    end

    instrument_authorized_actors
  end

  def replace_dismissal_restricted_actors(user_ids:, team_ids:, integration_ids: nil)
    preserve_dismissal_restrictions

    integration_ids ||= []

    if (user_ids.length + team_ids.length + integration_ids.length) > MAX_AUTHORIZED_ACTORS
      raise TooManyPermittedActors.new("Only #{MAX_AUTHORIZED_ACTORS} users, teams, and apps can be specified.")
    end

    # Use update_column so `authorized_dismissal_actors_only=` isn't called.
    update_column(:authorized_dismissal_actors_only, true) unless restricted_dismissed_reviews?

    review_dismissal_allowances.destroy_all

    repository&.teams(immediate_only: false)&.where(id: team_ids)&.each do |team|
      add_allowed_review_dismissal_actor(team)
    end

    User.where(id: user_ids).each do |user|
      add_allowed_review_dismissal_actor(user)
    end

    if integration_ids.any?
      IntegrationInstallation.with_repository(repository).joins(:integration).
        where(integrations: { id: integration_ids }).each do |integration_installation|
          add_allowed_review_dismissal_actor(integration_installation)
        end
    end

    instrument_dismissal_restricted_actors
  end

  def dismissal_restricted_users
    review_dismissal_allowances.where(actor_type: "User").map(&:actor).compact
  end

  def dismissal_restricted_teams
    review_dismissal_allowances.where(actor_type: "Team").map(&:actor).compact
  end

  def dismissal_restricted_integration_installations
    review_dismissal_allowances.where(actor_type: "IntegrationInstallation").map(&:actor).compact
  end

  def replace_branch_actor_allowances(policy, user_ids:, team_ids:, integration_ids:)
    user_ids ||= []
    team_ids ||= []
    integration_ids ||= []

    if (user_ids.length + team_ids.length + integration_ids.length) > MAX_AUTHORIZED_ACTORS
      raise TooManyPermittedActors.new("Only #{MAX_AUTHORIZED_ACTORS} users, teams, and apps can be specified.")
    end

    branch_actor_allowances_for_policy(policy).destroy_all

    if team_ids.any?
      repository&.teams(immediate_only: false)&.where(id: team_ids)&.each do |team|
        add_branch_policy_allowance_actor(team, policy)
      end
    end

    if user_ids.any?
      User.where(id: user_ids).each do |user|
        add_branch_policy_allowance_actor(user, policy)
      end
    end

    if integration_ids.any?
      IntegrationInstallation.with_repository(repository).joins(:integration).
        where(integrations: { id: integration_ids }).each do |integration_installation|
          add_branch_policy_allowance_actor(integration_installation, policy)
        end
    end

    instrument_branch_allowances(policy)
  end

  def branch_actor_allowances_for_policy(policy)
    branch_actor_allowances.where(policy: BranchActorAllowance::TYPES[policy])
  end

  def branch_actor_allowance_has_any?(policy)
    branch_actor_allowances_for_policy(policy).exists?
  end

  def branch_actor_allowance_users(policy)
    branch_actor_allowances_for_policy(policy).where(actor_type: "User").map(&:actor).compact
  end

  def branch_actor_allowance_teams(policy)
    branch_actor_allowances_for_policy(policy).where(actor_type: "Team").map(&:actor).compact
  end

  def branch_actor_allowance_integration_installations(policy)
    branch_actor_allowances_for_policy(policy).where(actor_type: "IntegrationInstallation").map(&:actor).compact
  end

  def authorized_actor_names
    authorized_users.pluck(:login) + authorized_teams.pluck(:name) + authorized_integration_slugs
  end

  def instrument_authorized_actors
    instrument :authorized_users_teams, {
      name: name,
      authorized_actors: authorized_actor_names,
      authorized_actors_only: authorized_actors_only,
    }
  end

  def instrument_dismissal_restricted_actors
    authorized_dismissal_actor_names = dismissal_restricted_users.map(&:to_s) + dismissal_restricted_teams.map(&:to_s) +
    dismissal_restricted_integration_slugs

    instrument :dismissal_restricted_users_teams, {
      name: name,
      authorized_actors: authorized_dismissal_actor_names,
      authorized_actors_only: authorized_dismissal_actors_only,
    }
  end

  def instrument_branch_allowances(policy)
    authorized_allowances_actor_names = branch_actor_allowance_users(policy).map(&:to_s) + branch_actor_allowance_teams(policy).map(&:to_s) +
    branch_actor_allowances_integration_slugs(policy)

    instrument :branch_allowances, {
      name: name,
      authorized_actors: authorized_allowances_actor_names,
      policy: policy
    }
  end

  # Public: The list of users, teams or IntegrationInstallations that updating this branch is restricted to
  #
  # Returns an Array of Users, Teams and IntegrationInstallations
  def authorized_actors
    return [] unless has_authorized_actors?

    authorized_users.to_a + authorized_teams.to_a + authorized_integration_installations.to_a
  end

  # Public: Get the Users authorized to push to this protected branch
  def authorized_users
    return [] unless has_authorized_actors?

    User.where(id: authorized_user_ids)
  end

  # Public: Get User ids authorized to push to this protected branch
  def authorized_user_ids
    return [] unless has_authorized_actors?

    Ability.where(
      actor_type: "User",
      subject_id: id,
      subject_type: "ProtectedBranch",
      priority: Ability.priorities[:direct],
    ).pluck(:actor_id)
  end

  # Public: Get the Teams authorized to push to this protected branch
  def authorized_teams
    return [] unless has_authorized_actors?

    Team.where(id: authorized_team_ids)
  end

  # Public: Get the Teams authorized to push to this protected branch
  def authorized_teams_with_preloaded_org
    return [] unless has_authorized_actors?

    Team.includes(:organization).where(id: authorized_team_ids)
  end

  # Public: Get Team ids authorized to push to this protected branch
  def authorized_team_ids
    return [] unless has_authorized_actors?

    Ability.where(
      actor_type: "Team",
      subject_id: id,
      subject_type: "ProtectedBranch",
      priority: Ability.priorities[:direct],
    ).pluck(:actor_id)
  end

  # Public: Get the IntegrationInstallations authorized to push to this protected branch
  def authorized_integration_installations
    return [] unless has_authorized_actors?

    IntegrationInstallation.where(id: authorized_integration_installation_ids)
  end

  # Public: Get IntegrationInstallations ids authorized to push to this protected branch
  def authorized_integration_installation_ids
    return [] unless has_authorized_actors?

    Permissions::Service.actor_ids_granted_permission(
      actor_type: "IntegrationInstallation",
      subject_type: "ProtectedBranch/contents",
      subject_ids: [self.id],
      action: Ability.actions[:write],
    )
  end

  # Public: The integration ids for the authorized installations
  def authorized_integration_ids
    return [] unless has_authorized_actors?

    authorized_integration_installations.pluck(:integration_id)
  end

  # Public: The integrations for the authorized installations
  def authorized_integrations
    return [] unless has_authorized_actors?

    Integration.where(id: authorized_integration_ids)
  end

  # Public: Has the number of restricted actors been reached?
  #
  # Returns Boolean
  def authorized_actors_limit_reached?
    authorized_actors.size >= MAX_AUTHORIZED_ACTORS
  end

  # Public: Has the number of restricted actors been reached?
  #
  # Returns Boolean
  def dismissal_restricted_actors_limit_reached?
    review_dismissal_allowances.size >= MAX_AUTHORIZED_ACTORS
  end

  # Public: Has the number of allowed actors been reached?
  #
  # Returns Boolean
  def branch_actor_allowance_limit_reached?(policy)
    branch_actor_allowances_for_policy(policy).size >= MAX_AUTHORIZED_ACTORS
  end

  # ProtectedBranch#authorized? has moved to:
  # app/models/protected_branch/permissions_dependency.rb

  # Public: the name of this branch, but tagged as UTF-8 and scrubbed so that it
  # it suitable for display.  +name+ is binary and *should not* be displayed
  # as a raw value in HTML.  Use this method instead.
  #
  # When should I use this method:
  #
  # * When *displaying* the protected branch name (in HTML or an email)
  #
  # When should I not use this method:
  #
  # * Communicating with GitRPC
  # * Constructing URLs
  def name_for_display
    name.dup.force_encoding("UTF-8").scrub!
  end

  # Checks to see if the actor who is passed in is in the list of allowed dismissers
  #
  # actor - the current_user viewing the page
  #
  # returns false if the actor is not logged_in
  # returns true if the actor is an admin and admin restrictions are not turned on
  # returns true if actor is in the list of specified users
  # returns true if actor is on one of the specified teams or children of those teams
  def review_dismissable_by?(actor)
    return false unless actor
    return true if !admin_enforced? && repository&.resources&.administration&.writable_by?(actor)
    return true if review_dismissal_allowances.where(actor_id: actor.id, actor_type: "User").any?

    if actor.is_a?(Bot)
      integration_installations = dismissal_restricted_integration_installations
      return false unless integration_installations.any?

      return IntegrationInstallation.where(id: integration_installations.map(&:id))
        .joins(:integration)
        .where({ integrations: { id: T.must(actor.integration).id } })
        .any?
    end

    teams = dismissal_restricted_teams
    teams.any? && Team.member_of?(teams.map(&:id), actor.id, immediate_only: false)
  end

  def deep_copy_as!(name:, creator: nil, entry_point: nil)
    protected_branch = dup
    protected_branch.name = name
    protected_branch.creator = creator if creator

    # after_save callback update_abilities_and_instrument_changes requires the entry_point to be set
    protected_branch.save_with_args!(entry_point: entry_point)

    review_dismissal_allowances.each do |review_dismissal_allowance|
      protected_branch.review_dismissal_allowances.create!(actor: review_dismissal_allowance.actor)
    end

    branch_actor_allowances.each do |branch_actor_allowance|
      protected_branch.branch_actor_allowances.create!(actor: branch_actor_allowance.actor, policy: branch_actor_allowance.policy, repository_id: repository_id)
    end

    required_status_checks.each do |required_status_check|
      protected_branch.required_status_checks.create!(context: required_status_check.context)
    end

    if has_authorized_actors?
      protected_branch.replace_authorized_actors(user_ids: authorized_user_ids, team_ids: authorized_team_ids,
                                                          integration_ids: authorized_integration_ids, entry_point: entry_point)
    end

    protected_branch
  end

  BRANCH_PROTECTION_RULE = "BranchProtectionRule".freeze
  def platform_type_name
    BRANCH_PROTECTION_RULE
  end

  # Make sure these can never return true unless the corresponding feature is enabled
  # for the repo or owner
  def ignore_approvals_from_contributors?
    repository&.disqualify_pr_pushers_from_approving_feature_enabled? && super
  end

  def target_for_conditional_access
    repository&.target_for_conditional_access
  end

  # Public: Destroys the protected branch and propagates kwargs to AR callback methods
  #
  # callback_args - keyword arguments to propagate to AR callback methods
  def destroy_with_args(**callback_args)
    @callback_args = callback_args
    self.destroy
  end

  # Public: Destroys the protected branch and propagates kwargs to AR callback methods
  #
  # callback_args - keyword arguments to propagate to AR callback methods
  def destroy_with_args!(**callback_args)
    @callback_args = callback_args
    self.destroy!
  end

  # Public: Saves the protected branch and propagates kwargs to AR callback methods
  #
  # callback_args - keyword arguments to propagate to AR callback methods
  def save_with_args(**callback_args)
    @callback_args = callback_args
    self.save
  end

  # Public: Saves the protected branch and propagates kwargs to AR callback methods
  #
  # callback_args - keyword arguments to propagate to AR callback methods
  def save_with_args!(**callback_args)
    @callback_args = callback_args
    self.save!
  end

  def skip_branch_protection_enabled_check
    @skip_ensure_branch_protection_enabled = true
  end

  private

  # Private: derive allow_force_pushes_enforcement_level value from block_force_pushes_enforcement_level
  def derive_force_pushes_enforcement_level
    self.allow_force_pushes_enforcement_level = INVERTED_LEVELS[block_force_pushes_enforcement_level]
  end

  # Private: derive allow_deletions_enforcement_level value from block_deletions_enforcement_level
  def derive_deletions_enforcement_level
    self.allow_deletions_enforcement_level = INVERTED_LEVELS[block_deletions_enforcement_level]
  end

  # Branch names can be split into different components (the parts between `/`).
  # This is a list of characters that can not be part of such a component for a rule.
  RULE_COMPONENT_CHARS = /[^\x00-\x1F\s\t\\:\^~\/]/
  VALID_RULE = /\A#{RULE_COMPONENT_CHARS}+(\/#{RULE_COMPONENT_CHARS}+)*\z/

  def rule_is_valid
    return if name.nil? || name.b.match?(VALID_RULE)

    errors.add :rule, "is invalid"
  end

  # Internal: if linear history is enforced, ensure that the associated repo permits a merging method that doesn't
  # create a merge commit.
  def ensure_consistent_merge_strategies
    return if !required_linear_history_enabled? ||
      repository.nil? ||
      repository&.squash_merge_allowed? ||
      repository&.rebase_merge_allowed?

    errors.add :linear_history_requirement_enforcement_level,
      "cannot enforce linear history without a non-merge strategy enabled"
  end

  # Internal: if linear history is enforced, ensure associated merge queue uses
  # a valid merge strategy
  def ensure_consistent_merge_strategy_for_merge_queue
    return unless required_linear_history_enabled?
    return unless merge_queue_enabled?

    # merge_queue_settings_hash is present only when updating via the frontend form
    return if merge_queue_settings_hash && merge_queue_settings_hash[:merge_method] != "merge"
    return if !merge_queue_settings_hash && merge_queue&.merge_method != "merge"

    errors.add :branch_protection_rule,
      "cannot require linear history when merge queue uses 'Merge commit' as its merge method. Set merge method to 'Squash and merge' or 'Rebase and merge' first."
  end

  # Internal: merge queue can only be enabled for a qualified branch name rule
  def ensure_qualified_branch_name_for_merge_queue
    return unless merge_queue_enabled?
    return unless wildcard_rule?

    errors.add :merge_queue_enforcement_level, "can only be enabled for qualified branch names"
  end

  def ensure_branch_protection_enabled
    return if @skip_ensure_branch_protection_enabled

    if repository && BranchProtectionsConfig.new(T.must(repository)).branch_protection_disabled?
      errors.add :repository, "branch protection is disabled. To add or edit branch protection rules, please re-enable branch protection."
    end
  end

  # Internal: prevent branch name changes if the merge queue is enabled
  def prevent_branch_name_change_for_merge_queue
    return unless merge_queue_enabled?
    return unless name_changed?

    errors.add :name, "cannot be updated when the merge queue is enabled"
  end

  # Internal: prevent protected branches for Merge Queue
  def prevent_required_deployments_for_merge_queue
    return unless required_deployments_enabled?
    return unless merge_queue_enabled?
    return if T.must(repository).feature_enabled?(:merge_queue_deploy_then_merge) || T.must(repository).github_owned?

    errors.add :required_deployments_enforcement_level, "cannot be enabled when the merge queue is enabled"
  end

  # Private: If authorized_actors_only changes from true to false, remove all
  # abilities on this protected branch and instrument the changes. Changing from
  # false to true isn't handled here because it is done in
  # `replace_authorized_actors`
  def update_abilities_and_instrument_changes
    if authorized_actors_only_before_last_save == true && authorized_actors_only == false
      if @callback_args.nil?
        @callback_args = {}
      end

      unless @callback_args.key?(:entry_point)
        @callback_args[:entry_point] = :unknown_protected_branch_save
      end

      clear_authorized_actor_abilities_and_permissions
      instrument_authorized_actors
    end
  end

  # Private: Set `create_protected` to false when `authorized_actors_only` is false
  def sync_create_protected
    self["create_protected"] = false unless authorized_actors_only
  end

  def clear_authorized_actor_abilities_and_permissions
    Ability.transaction do
      # Delete abilities for Users and Teams
      Ability.clear(self, async: false)

      clear_app_permissions
    end
  end

  # Private: Return the enforcement level that should be used for newly enabled `_enforcement_level` enum fields that
  # should be kept consistent with the current value of `admin_enforced?`.
  def enabled_enforcement_level(non_admins_possible:)
    !non_admins_possible || admin_enforced? ? LEVELS[:everyone] : LEVELS[:non_admins]
  end

  # Private: Return the enforcement level that should be used for disabled `_enforcement_level` enum fields.
  def disabled_enforcement_level
    LEVELS[:off]
  end

  # Internal: The integration slugs for the authorized installations
  def authorized_integration_slugs
    return [] unless has_authorized_actors?

    authorized_integration_installations.joins(:integration).pluck(:"integrations.slug")
  end

  # Internal: The integration slugs for the restricted dismissal installations
  def dismissal_restricted_integration_slugs
    integration_installations = dismissal_restricted_integration_installations
    return [] unless integration_installations.any?

    IntegrationInstallation.where(id: integration_installations.map(&:id)).joins(:integration).pluck(:"integrations.slug")
  end

  # Internal: The integration slugs for the branch allowances installations
  def branch_actor_allowances_integration_slugs(policy)
    integration_installations = branch_actor_allowance_integration_installations(policy)
    return [] unless integration_installations.any?

    IntegrationInstallation.where(id: integration_installations.map(&:id)).joins(:integration).pluck(:"integrations.slug")
  end

  # Internal: Creates ReviewDismissalAllowance for actor
  #
  # Returns the ReviewDismissalAllowance record.
  def add_allowed_review_dismissal_actor(actor)
    return unless repository_writable_by?(actor)

    review_dismissal_allowances.create(actor: actor)
  end

  # Internal: Creates BranchActorAllowance for actor
  #
  # Returns the BranchActorAllowance record.
  def add_branch_policy_allowance_actor(actor, policy)
    return unless repository_writable_by?(actor)

    branch_actor_allowances.create(actor: actor, policy: BranchActorAllowance::TYPES[policy], repository_id: repository_id)
  end

  # Internal: Adds an authorized actor
  #
  # Returns the Ability record.
  def add_authorized_actor(actor)
    return unless repository_writable_by?(actor)

    if actor.is_a?(IntegrationInstallation)
      ::Permissions::Service.grant_app_permission(actor: actor, subject: resources.contents, action: :write)
    else
      grant actor, :write
    end
  end

  # Internal: Used by abilities to ensure that only Users or Teams can be granted abilities
  #
  # See Ability::Subject#grant? for more info.
  def grant?(actor, action)
    (actor.is_a?(User) || actor.is_a?(Team)) && super
  end

  # Internal: Can this actor override protected branch settings
  #
  # actor - User/Bot, or PublicKey to check for
  #
  # Returns Boolean
  def can_override_protection?(enforcement_level:, actor:)
    case enforcement_level
    when "off"
      true
    when "non_admins"
      case actor
      when PublicKey
        # According to https://github.com/github/github/issues/69229, writable deploy keys are always treated as admins
        write_deploy_key?(actor)
      when Bot
        repository&.resources&.administration&.writable_by?(actor)
      when User
        ::Permissions::Enforcer.authorize(
          action: :bypass_branch_protection,
          actor: actor,
          subject: self
        ).allow?
      else
        raise TypeError, "expected actor to be a User, Bot, or PublicKey, but was #{actor.class}"
      end
    when "everyone"
      false
    end
  end

  def is_resource_admin_writable?(actor)
    science "protected_branch.bypass_protection_fgp_result" do |e|
      e.use do
        resource_admin_writable = repository&.resources&.administration&.writable_by?(actor)
        log_resource_admin_writable_result(actor: actor, result: resource_admin_writable)
        resource_admin_writable
      end
      e.try do
        ::Permissions::Enforcer.authorize(
          action: :bypass_branch_protection,
          actor: actor,
          subject: self
        ).allow?
      end
    end
  end

  # Temporary logging added for https://github.com/github/repos/issues/1105
  def log_resource_admin_writable_result(actor:, result:)
    return unless GitHub.flipper[:log_protected_branch_admin_override_allowed].enabled?(repository)

    GitHub.logger.info("resource_admin_writable", {
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": repository_id,
      "gh.actor.id": actor.try(:id),
      "gh.actor.type": actor.class.name,
      "gh.branch_protection_rule.id": id,
      "gh.branch_protection_rule.result": result ? "true" : "false",
    })
  end

  # Temporary logging added for https://github.com/github/repos/issues/1105
  def log_can_override_protection_result(type:, enforcement_level:, actor:, result:)
    return unless GitHub.flipper[:log_protected_branch_admin_override_allowed].enabled?(repository)

    GitHub.logger.info("can_override_protection", {
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.repo.id": repository_id,
      "gh.actor.id": actor.try(:id),
      "gh.actor.type": actor.class.name,
      "gh.branch_protection_rule.id": id,
      "gh.branch_protection_rule.type": type,
      "gh.branch_protection_rule.enforcement_level": enforcement_level,
      "gh.branch_protection_rule.result": result ? "allowed" : "denied",
    })
  end

  # Private: Instrument creation of this ProtectedBranch
  def instrument_create
    instrument :create, {
      user: creator,
      authorized_actor_names: authorized_actor_names,
      required_status_checks_enforcement_level: LEVELS[required_status_checks_enforcement_level],
      strict_required_status_checks_policy: read_attribute(:strict_required_status_checks_policy),
      dismiss_stale_reviews_on_push: read_attribute(:dismiss_stale_reviews_on_push),
      require_code_owner_review: read_attribute(:require_code_owner_review),
      require_last_push_approval: read_attribute(:require_last_push_approval),
      ignore_approvals_from_contributors: read_attribute(:ignore_approvals_from_contributors),
      pull_request_reviews_enforcement_level: LEVELS[pull_request_reviews_enforcement_level],
      required_approving_review_count: read_attribute(:required_approving_review_count),
      signature_requirement_enforcement_level: LEVELS[signature_requirement_enforcement_level],
      linear_history_requirement_enforcement_level: LEVELS[linear_history_requirement_enforcement_level],
      admin_enforced: read_attribute(:admin_enforced),
      allow_force_pushes_enforcement_level: INVERTED_LEVELS[block_force_pushes_enforcement_level],
      allow_deletions_enforcement_level: INVERTED_LEVELS[block_deletions_enforcement_level],
      required_deployments_enforcement_level: LEVELS[required_deployments_enforcement_level],
      required_review_thread_resolution_enforcement_level: LEVELS[required_review_thread_resolution_enforcement_level],
      merge_queue_enforcement_level: LEVELS[merge_queue_enforcement_level],
      enforcement_level: lock_branch_enforcement_level.dasherize,
      lock_branch_enforcement_level: LEVELS[lock_branch_enforcement_level],
      lock_allows_fetch_and_merge: read_attribute(:lock_allows_fetch_and_merge),
      create_protected: read_attribute(:create_protected),
      name: read_attribute(:name),
    }

    GlobalInstrumenter.instrument("branch_protection_rule.create", {
      actor: creator,
      repository: repository,
      repository_owner: repository&.owner,
      branch_protection_rule: self,
    })
  end

  # we need to invert the levels until the legacy block_* column names are renamed to allow_*
  # currently used for instrumenting update_allow_force_pushes_enforcement_level and update_allow_deletions_enforcement_level
  # tracked in https://github.com/github/ce-oss-happiness/issues/69
  INVERTED_LEVELS = {
    off: LEVELS[:everyone],
    non_admins: LEVELS[:off],
    everyone: LEVELS[:off],
  }.with_indifferent_access.freeze

  # Private: Instrument update of this record with the new values

  def instrument_update
    actor = (User.find_by(id: GitHub.context[:actor_id]) || creator)
    instrument :update, {
      user: actor,
      authorized_actor_names: authorized_actor_names,
      previous_changes: @previous_changes || previous_changes,
      previous_authorized_actors_only: @previous_authorized_actors_only,
      previous_authorized_actor_names: @previous_authorized_actor_names,
      previous_status_checks_contexts: @previous_status_checks_contexts,
      previous_authorized_dismissal_actors_only: @previous_authorized_dismissal_actors_only,
    }.compact
    @previous_status_checks_contexts = nil
    @previous_authorized_actor_names = nil
    @previous_authorized_actors_only = nil
    @previous_authorized_dismissal_actors_only = nil
    @saved_changes = @saved_changes || {}

    GlobalInstrumenter.instrument("branch_protection_rule.update", {
      actor: actor,
      repository: repository,
      repository_owner: repository&.owner,
      branch_protection_rule: self,
    })

    if saved_change_to_required_status_checks_enforcement_level? || @saved_changes[:required_status_checks_enforcement_level]
      instrument :update_required_status_checks_enforcement_level, {
          required_status_checks_enforcement_level: LEVELS[required_status_checks_enforcement_level],
        }
    end

    if saved_change_to_strict_required_status_checks_policy? || @saved_changes[:strict_required_status_checks_policy]
      instrument :update_strict_required_status_checks_policy, {
          strict_required_status_checks_policy:
            read_attribute(:strict_required_status_checks_policy),
        }
    end

    if saved_change_to_dismiss_stale_reviews_on_push? || @saved_changes[:dismiss_stale_reviews_on_push]
      instrument :dismiss_stale_reviews, {
        dismiss_stale_reviews_on_push:
          read_attribute(:dismiss_stale_reviews_on_push),
      }
    end

    if saved_change_to_require_code_owner_review? || @saved_changes[:require_code_owner_review]
      instrument :update_require_code_owner_review, {
        require_code_owner_review:
          read_attribute(:require_code_owner_review),
      }
    end

    if saved_change_to_require_last_push_approval? || @saved_changes[:require_last_push_approval]
      instrument :update_require_last_push_approval, {
        require_last_push_approval:
          read_attribute(:require_last_push_approval),
      }
    end

    if saved_change_to_ignore_approvals_from_contributors? || @saved_changes[:ignore_approvals_from_contributors]
      instrument :update_ignore_approvals_from_contributors, {
        ignore_approvals_from_contributors:
          read_attribute(:ignore_approvals_from_contributors),
      }
    end

    if saved_change_to_pull_request_reviews_enforcement_level? || @saved_changes[:pull_request_reviews_enforcement_level]
      instrument :update_pull_request_reviews_enforcement_level, {
        pull_request_reviews_enforcement_level: LEVELS[pull_request_reviews_enforcement_level],
      }
    end

    if saved_change_to_required_approving_review_count? || @saved_changes[:required_approving_review_count]
      instrument :update_required_approving_review_count, {
        required_approving_review_count:
          read_attribute(:required_approving_review_count),
      }
    end

    if saved_change_to_signature_requirement_enforcement_level? || @saved_changes[:signature_requirement_enforcement_level]
      instrument :update_signature_requirement_enforcement_level, {
        signature_requirement_enforcement_level: LEVELS[signature_requirement_enforcement_level],
      }
    end

    if saved_change_to_linear_history_requirement_enforcement_level? || @saved_changes[:linear_history_requirement_enforcement_level]
      instrument :update_linear_history_requirement_enforcement_level, {
        linear_history_requirement_enforcement_level: LEVELS[linear_history_requirement_enforcement_level],
      }
    end

    # todo: add audit log action when saving change to strict application

    if saved_change_to_admin_enforced? || @saved_changes[:admin_enforced]
      instrument :update_admin_enforced, {
        admin_enforced:
          read_attribute(:admin_enforced),
      }
    end

    if saved_change_to_block_force_pushes_enforcement_level? || @saved_changes[:allow_force_pushes_enforcement_level]
      instrument :update_allow_force_pushes_enforcement_level, {
        allow_force_pushes_enforcement_level: INVERTED_LEVELS[block_force_pushes_enforcement_level],
      }
    end

    if saved_change_to_block_deletions_enforcement_level? || @saved_changes[:allow_deletions_enforcement_level]
      instrument :update_allow_deletions_enforcement_level, {
        allow_deletions_enforcement_level: INVERTED_LEVELS[block_deletions_enforcement_level],
      }
    end

    if saved_change_to_required_deployments_enforcement_level? || @saved_changes[:required_deployments_enforcement_level]
      instrument :update_required_deployments_enforcement_level, {
        required_deployments_enforcement_level: LEVELS[required_deployments_enforcement_level],
      }
    end

    if saved_change_to_required_review_thread_resolution_enforcement_level? || @saved_changes[:required_review_thread_resolution_enforcement_level]
      instrument :update_required_review_thread_resolution_enforcement_level, {
        required_review_thread_resolution_enforcement_level: LEVELS[required_review_thread_resolution_enforcement_level],
      }
    end

    if saved_change_to_merge_queue_enforcement_level? || @saved_changes[:merge_queue_enforcement_level]
      instrument :update_merge_queue_enforcement_level, {
        merge_queue_enforcement_level: LEVELS[merge_queue_enforcement_level],
      }
    end

    if saved_change_to_lock_branch_enforcement_level? || @saved_changes[:lock_branch_enforcement_level]
      instrument :update_lock_branch_enforcement_level, {
        enforcement_level: lock_branch_enforcement_level.dasherize,
        lock_branch_enforcement_level: LEVELS[lock_branch_enforcement_level],
      }
    end

    if saved_change_to_lock_allows_fetch_and_merge? || @saved_changes[:lock_allows_fetch_and_merge]
      instrument :update_lock_allows_fetch_and_merge, {
        lock_allows_fetch_and_merge: read_attribute(:lock_allows_fetch_and_merge),
      }
    end

    if saved_change_to_create_protected? || @saved_changes[:create_protected]
      instrument :update_create_protected, {
        create_protected: read_attribute(:create_protected),
      }
    end

    if saved_change_to_name? || @saved_changes[:name]
      instrument :update_name, {
        name:
          read_attribute(:name),
        old_name: name_before_last_save || @name_before_save
      }
    end
  end

  # Private: Instrument deletion of this record with the actor who did it
  def instrument_destroy
    actor = (User.find_by(id: GitHub.context[:actor_id]) || creator)
    instrument :destroy, {
      authorized_actor_names: authorized_actor_names,
      required_status_checks_enforcement_level: LEVELS[required_status_checks_enforcement_level],
      strict_required_status_checks_policy: read_attribute(:strict_required_status_checks_policy),
      dismiss_stale_reviews_on_push: read_attribute(:dismiss_stale_reviews_on_push),
      require_code_owner_review: read_attribute(:require_code_owner_review),
      require_last_push_approval: read_attribute(:require_last_push_approval),
      ignore_approvals_from_contributors: read_attribute(:ignore_approvals_from_contributors),
      pull_request_reviews_enforcement_level: LEVELS[pull_request_reviews_enforcement_level],
      required_approving_review_count: read_attribute(:required_approving_review_count),
      signature_requirement_enforcement_level: LEVELS[signature_requirement_enforcement_level],
      linear_history_requirement_enforcement_level: LEVELS[linear_history_requirement_enforcement_level],
      admin_enforced: read_attribute(:admin_enforced),
      allow_force_pushes_enforcement_level: INVERTED_LEVELS[block_force_pushes_enforcement_level],
      allow_deletions_enforcement_level: INVERTED_LEVELS[block_deletions_enforcement_level],
      required_deployments_enforcement_level: LEVELS[required_deployments_enforcement_level],
      required_review_thread_resolution_enforcement_level: LEVELS[required_review_thread_resolution_enforcement_level],
      merge_queue_enforcement_level: LEVELS[merge_queue_enforcement_level],
      enforcement_level: lock_branch_enforcement_level.dasherize,
      lock_branch_enforcement_level: LEVELS[lock_branch_enforcement_level],
      lock_allows_fetch_and_merge: read_attribute(:lock_allows_fetch_and_merge),
      create_protected: read_attribute(:create_protected),
      name: read_attribute(:name),
    }



    GlobalInstrumenter.instrument("branch_protection_rule.destroy", {
      actor: actor,
      repository: repository,
      repository_owner: repository&.owner,
      branch_protection_rule: self,
    })
  end

  def synchronize_search_index
    if (repo = repository)
      open_pull_request_ids = repo.open_pull_requests_on_base_ref(name).pluck(:pull_request_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      open_pull_request_ids.each do |pr_id|
        Search.add_to_search_index("pull_request", pr_id)
      end
    end
  end

  # Private: syncs the merge queue based on `merge_queue_enforcement_level`.
  def sync_merge_queue
    return unless GitHub.merge_queues_enabled?

    if merge_queue_enabled?
      unless merge_queue
        create_merge_queue!(repository: repository, branch: name)
      end
      if merge_queue_settings_hash.present?
        merge_queue&.update!(merge_queue_settings_hash)
      end

    # If a MergeQueue already exists, but the branch has merge queue disabled,
    # clear and delete it.
    elsif merge_queue.present?
      current_actor = User.find_by(id: GitHub.context[:actor_id]) || User.ghost
      MergeQueue.transaction do
        merge_queue&.force_clear(actor: current_actor)
        merge_queue&.destroy!
      rescue ActiveRecord::RecordNotFound
        # No-op: near-simultaneous deletion in another process
      end
    end
  end

  def ensure_no_duplicate_merge_queue
    return unless GitHub.merge_queues_enabled?
    return unless GitHub.flipper[:block_duplicate_protected_branch_merge_queue].enabled?(repository)

    if merge_queue_enabled? && merge_queue.nil? && repository&.merge_queues&.exists?(branch: name)
      errors.add(:merge_queue, "cannot be enabled when a merge queue already exists for this branch. A merge queue may already be configured through rulesets.")
    end
  end

  def enqueue_auto_merge_job_if_enabled
    # We use auto-merge as part of merge queue and enqueueing a PR to deploy before
    # the checks finish creates an auto merge request. In this case we still want to
    # sync these auto merge requests as well, even if auto merge is not turned on at
    # the repo level.
    return unless merge_queue_enabled? || repository&.auto_merge_allowed?
    AutoMergeSynchronizeOpenPullRequestsJob.perform_later(repository: repository, base_ref: name)
  end

  def event_payload
    payload = {
      event_prefix => self,
      :repo => repository,
      :name => name,
    }

    if (repo = repository) && repo.in_organization?
      payload[:org] = repo.organization
    end

    payload
  end

  # Internal: Verify that the creator is a User, not something else (like an
  # Organization).
  def creator_must_be_user
    # We only run the validation when creator_id_changed? because Users can be
    # transformed to Organizations behind the scenes. When that happens we
    # still want the protected branches created by the transformed user to be
    # able to be updated.
    if creator_id_changed? && creator && (!creator&.user? && !creator.is_a?(Bot))
      errors.add :creator_id, "must be a User"
    end
  end

  # Internal: is the actor a writable deploy key? These are treated as admins
  # for the purposes of overriding protected branch requirements. See
  # https://github.com/github/github/issues/69229 for discussion.
  def write_deploy_key?(actor)
    repository&.owner == actor.ability_delegate &&
      (actor.respond_to?(:read_only?) && !actor.read_only?)
  end

  StatusContextDiff = Struct.new(:create, :destroy)

  # Internal: Compare the given list of contexts to the current set of required
  # contexts and return a StatusContextDiff describing the difference between
  # the two.
  #
  # contexts - Array of String Status context names
  #
  # Returns a StatusContextDiff.
  def diff_status_contexts(contexts)
    existing_contexts = self.required_status_checks.map(&:context)

    contexts_to_create  = contexts - existing_contexts
    contexts_to_destroy = existing_contexts - contexts

    StatusContextDiff.new(contexts_to_create, contexts_to_destroy)
  end

  def diff_environments(environments)
    existing_environments = self.required_deployments.map(&:environment)

    environments_to_create  = environments - existing_environments
    environments_to_destroy = existing_environments - environments

    [environments_to_create, environments_to_destroy]
  end

  # Private: Serializes this ProtectedBranch as a webhook payload for any apps
  # that listen for Hook::Event::BranchProtectionRule events. Under normal
  # circumstances we deliver webhook events using instrumentation, but this must
  # be called as a before_destroy to serialize the webhook payload before the
  # record becomes unavailable.
  def generate_webhook_payload
    actor = (User.find_by(id: GitHub.context[:actor_id]) || creator) || User.ghost
    event = Hook::Event::BranchProtectionRuleEvent.new(
      action: :deleted,
      authorized_actor_names: authorized_actor_names,
      protected_branch_id: self.id,
      actor_id: actor&.id,
      triggered_at: Time.now,
    )
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  # Private: Queue the payload generated above for delivery to Hookshot.
  def queue_webhook_delivery
    raise "'generate_webhook_payload' must be called before `queue_webhook_delivery'" unless defined?(@delivery_system)

    @delivery_system&.deliver_later
  end

  # Private: Preserve the list of associated status checks through updates, so
  # webhooks can include the previous value on "change" payload
  def preserve_status_checks_contexts
    @previous_status_checks_contexts = self.required_status_checks.pluck(:context)
  end

  # Private: Preserve the setting and list of authorized actor names through
  # updates, so webhooks can include the previous value on "change" payload
  def preserve_authorized_actor_info
    @previous_authorized_actors_only = authorized_actors_only
    @previous_authorized_actor_names = authorized_actor_names
  end

  # Private: Preserve the dismissal actors setting through
  # updates, so webhooks can include the previous value on "change" payload
  def preserve_dismissal_restrictions
    @previous_authorized_dismissal_actors_only = authorized_dismissal_actors_only
  end

  # Private: Preserve saved changes through reloads
  # so webhooks can use them to determine what changed
  def preserve_saved_changes
    @saved_changes = saved_changes
    @previous_changes = previous_changes
    @name_before_save = name_before_last_save if saved_change_to_name?
  end

  def clear_saved_changes
    @saved_changes = nil
    @previous_changes = nil
    @name_before_save = nil
  end
end
