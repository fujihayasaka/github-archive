# typed: false
# frozen_string_literal: true

# actions-specific functionality for repositories
module Repository::ActionsDependency
  extend ActiveSupport::Concern

  include ActionsPolicy::AccessPolicyDependency

  WORKFLOW_FILE_REGEX = /\A\.github\/(?:workflows(-lab)?\/[^\/]+\.ya?ml)\z/

  included do
    has_many :actions, class_name: "RepositoryAction", dependent: :destroy
    has_one :listed_action, -> { where(state: :listed) }, class_name: "RepositoryAction"

    has_many :integration_allowed_packages, dependent: :destroy

    scope :featured_actions, -> { actions.where(featured: true) }

    has_many :actions_artifacts, class_name: "Artifact"
  end

  # If an allowlist is defined at a higher level (org or business) we must respect those settings.
  # On GHES, the highest level for any repository is the Global Business
  def highest_level_allowlist(include_all_allowed: false)
    if include_all_allowed
      return @_highest_level_allowlist_all_allowed if defined?(@_highest_level_allowlist_all_allowed)
      allowlist = self.actions_allowlist

      if configuration_owner.respond_to?(:highest_level_allowlist)
        @_highest_level_allowlist_all_allowed = configuration_owner.highest_level_allowlist(include_all_allowed: true) || allowlist
      elsif configuration_owner&.configuration_owner.respond_to?(:highest_level_allowlist)
        @_highest_level_allowlist_all_allowed = configuration_owner.configuration_owner.highest_level_allowlist(include_all_allowed: true) || allowlist
      else
        @_highest_level_allowlist_all_allowed = allowlist
      end
    else
      return @_highest_level_allowlist if defined?(@_highest_level_allowlist)
      allowlist = self.actions_allowlist

      # Fix for unexpected data where all_allowed:true and sha_pinning_required:false
      # which is causing the allowlist to be enforced at the wrong level
      allowlist = nil if allowlist&.all_allowed?

      if configuration_owner.respond_to?(:highest_level_allowlist)
        @_highest_level_allowlist = configuration_owner.highest_level_allowlist || allowlist
      elsif configuration_owner&.configuration_owner.respond_to?(:highest_level_allowlist)
        @_highest_level_allowlist = configuration_owner.configuration_owner.highest_level_allowlist || allowlist
      else
        @_highest_level_allowlist = allowlist
      end
    end
  end

  def lowest_level_allowlist
    return @_lowest_level_allowlist if defined?(@_lowest_level_allowlist)
    return @_lowest_level_allowlist = actions_allowlist if actions_allowlist

    if configuration_owner.respond_to?(:lowest_level_allowlist)
      @_lowest_level_allowlist = configuration_owner.lowest_level_allowlist
    elsif configuration_owner&.configuration_owner.respond_to?(:lowest_level_allowlist)
      @_lowest_level_allowlist = configuration_owner.configuration_owner.lowest_level_allowlist
    end
  end

  def async_allows_all_actions?
    Promise.all([async_owner, async_actions_allowlist]).then do |owner, _allowlist|
      if owner.user?
        allows_all_actions?
      else
        Promise.all([owner.async_actions_allowlist, owner.async_business]).then do |_owner, business|
          if business.present?
            business.async_actions_allowlist.then do |_business_allowlist|
              allows_all_actions?
            end
          else
            allows_all_actions?
          end
        end
      end
    end
  end

  def closest_owner_allowlist
    configuration_owner.try(:async_actions_allowlist)&.sync || configuration_owner&.configuration_owner.try(:async_actions_allowlist)&.sync
  end

  def action_at_root
    actions.where(path: ["action.yml", "action.yaml"]).find(&:metadata_file)
  end

  def listable_action?
    public? && action_at_root.present?
  end

  def actions_app_installed?
    actions_app_installation.present?
  end

  def actions_enabled?
    !actions_disabled?
  end

  def async_actions_plan_owner
    self.async_owner.then do |owner|
      if owner.organization?
        owner.async_business.then do |business|
          ActionsPlanOwner.new(business || owner)
        end
      else
        ActionsPlanOwner.new(owner)
      end
    end
  end

  def action(base_path)
    # We assume the base_path is a folder path.
    path = base_path + "/Dockerfile"

    # "" as a base_path maps to the Dockerfile at the root of the repo.
    path = "Dockerfile" if base_path.to_s.empty?

    self.actions.find_by(path: path)
  end

  def dispatch_event(actor_id, event_type, client_payload = nil)
    input = {
      actor_id: actor_id,
      action: event_type,
      repository_id: id,
      branch: self.default_branch,
      client_payload: client_payload,
    }

    GitHub.instrument("repository_dispatch.create", input)
  end

  def dispatch_workflow_event(actor_id, workflow_path, ref, inputs = nil)
    input = {
      actor_id: actor_id,
      repository_id: id,
      ref: ref,
      workflow: workflow_path,
      inputs: inputs
    }
    GitHub.instrument("workflow_dispatch", input) if GitHub.actions_enabled?
  end

  def run_dynamic_workflow(actor:, workflow:, ref:, inputs:, workflow_name:, slug:, integration_name:, visibility: :DEFAULT, entry_point:, prevent_reruns: false)
    client = if dynamic_workflow_should_run_on_lab(integration_name)
      Launch::Twirp.deployer_lab_client
    else
      Launch::Twirp.deployer_client
    end

    client.run_dynamic_workflow(
      repository: self,
      integration_name: integration_name,
      actor: actor,
      workflow: workflow,
      ref: ref,
      inputs: inputs,
      workflow_name: workflow_name,
      slug: slug,
      visibility: visibility,
      prevent_reruns:,
    )
  end

  def dynamic_workflow_should_run_on_lab(integration_name)
    return false unless integration_name == GitHub.dependabot_github_app_slug || integration_name == "pages"
    self.feature_flag_enabled?(:launch_twirp_run_dynamic_workflow_lab, default: false)
  end

  def create_or_update_action(action_config)
    action = self.actions.where(path: action_config[:path]).first

    action_params = action_config.slice(:name, :path, :description, :icon_name, :color)

    # Create a new action if one doesn't exist.
    unless action
      return self.actions.create(action_params)
    end

    if action.unlisted?
      # Auto update an existing action if it's not Listed in Marketplace.
      action.assign_attributes(action_params)
      action.save if action.changed?
    end
  end

  def get_action_config_from_metadata_file(metadata_file)
    get_action_config_from_yml_file(metadata_file)
  end

  def runner_registration_token_scope
    "RegisterActionsRunner:#{id}"
  end

  # We want to split this token into create and delete in the future
  def runner_creation_token_scope
    runner_registration_token_scope
  end

  def runner_deletion_token_scope
    runner_registration_token_scope
  end

  def update_repository_actions
    return unless GitHub.actions_enabled?
    files_changed_on_head_matching_names(["action.yml", "action.yaml"]).each do |yml_file|
      action_config = get_action_config_from_yml_file(yml_file)
      # Move to the next entry if this isn't an Action.
      next unless action_config[:is_action]
      create_or_update_action(action_config)
    end
  end

  def update_repository_workflows(ref, before, after)
    return unless GitHub.actions_enabled?

    # When before is a null OID, the push is to a new repository
    # To ensure we get a diff for all the files added, we need to
    # use the EMPTY_TREE_OID rather than a null OID.
    before = GitHub::EMPTY_TREE_OID if before == GitHub::NULL_OID
    changed_files = rpc.native_read_diff_toc(before, after, nil)

    if ref == "refs/heads/#{default_branch}"
      # For now: we want to create, update, and remove workflow entities only when they
      # are pushed to the default branch
      changed_files.each do |changed_file|
        path = changed_file.path

        renamed = changed_file.status == Repositories::ChangedFile::RENAMING
        # Is the file currently considered a workflow?
        currently_a_workflow = path.match?(WORKFLOW_FILE_REGEX)
        # Was the file previously considered a workflow?
        was_a_workflow = changed_file.old_file.path.match?(WORKFLOW_FILE_REGEX)

        if renamed
          # For renames, we need to check the old file path as well the current to ensure
          # we delete the old workflow in cases where the new file is no longer a workflow
          next unless was_a_workflow || currently_a_workflow
        else
          next unless currently_a_workflow
        end

        # If the file was previously a workflow, check if an old workflow needs to be deleted
        if was_a_workflow
          deleted = changed_file.status == Repositories::ChangedFile::DELETION
          if renamed || deleted
            # Treat rename as deletion of the old workflow
            workflow = Actions::Workflow.find_by(repository: self, path: changed_file.old_file.path, imposer_repository_id: 0)
            workflow.update(state: "deleted", present_in_default_branch: false) if workflow
          end
        end

        # Don't try to create a new workflow entry if the file was renamed to a non-workflow file
        next if was_a_workflow && !currently_a_workflow

        added_or_modified = changed_file.status == Repositories::ChangedFile::ADDITION || changed_file.status == Repositories::ChangedFile::MODIFYING
        if added_or_modified || renamed
          parsed_workflow = Actions::ParsedWorkflow.parse_from_yaml(self, path)
          next unless parsed_workflow

          workflow = Actions::Workflow.find_by(repository: self, path: path, imposer_repository_id: 0)
          if workflow
            # Update an existing workflow. Also mark is as :active if it wasn't manually disabled
            new_state = workflow.disabled_manually? ? workflow.state : :active
            workflow.update(name: parsed_workflow.name, state: new_state, present_in_default_branch: true)

            GitHub.dogstats.increment("repository.workflows.updated", tags: ["status:modified"])
          else
            # Create a new workflow
            attrs = { path: path, repository: self, state: :active, name: parsed_workflow.name, present_in_default_branch: true }
            workflow = Actions::Workflow.new(attrs)
            workflow.save

            GitHub.dogstats.increment("repository.workflows.updated", tags: ["status:new"])
          end
        end
      end
    end
  end

  def can_use_actions_allowlist?
    can_use_actions_enterprise_features?(allow_legacy_plans: true)
  end

  def allow_team_or_pro_feature?
    can_use_actions_team_features? || can_use_actions_pro_features?
  end

  def can_use_environments?
    allow_team_or_pro_feature? || can_use_actions_enterprise_features? || can_use_environments_features_on_free_plans?
  end

  def can_use_environments_api?
    allow_team_or_pro_feature? || can_use_actions_enterprise_features? || can_use_environments_features_on_free_plans?
  end

  def can_use_deployment_protected_branch?
    allow_team_or_pro_feature? || can_use_actions_enterprise_features? || can_use_environments_features_on_free_plans?
  end

  def can_use_deployment_branch_gates?
    # Note: We don't allow all plans to use non-protected branch gates (timers, manual approvals, custom gates),
    # this still requires an Enterprise plan.
    can_use_actions_enterprise_features?
  end

  def owner_can_use_actions_enterprise_features?
    return false unless GitHub.actions_enabled?
    return true if GitHub.enterprise?
    self.owner.plan.business_plus? || self.owner.plan.enterprise?
  end

  def owner_can_use_actions_team_features?
    return false unless GitHub.actions_enabled?
    return true if GitHub.enterprise?
    owner_can_use_actions_enterprise_features? || self.owner.plan.business?
  end

  def owner_can_use_actions_pro_feature?
    return false unless GitHub.actions_enabled?
    self.owner.plan.pro?
  end

  def owner_can_use_larger_cloud_hosted_runners?
    return false unless owner.is_a?(Organization)
    owner.can_use_larger_runners?
  end

  def can_emit_actions_audit_logs?
    owner_can_use_actions_enterprise_features?
  end

  def set_default_workflow_permissions_for_new_repos
    return unless FeatureFlag.vexi.enabled_or_raise?(:actions_default_workflow_permissions_new_repos, owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return if owner.is_a?(Organization)
    set_actions_workflow_permission_can_approve_pr(false, owner)
    set_default_workflow_permissions("read", owner)
    true
  end

  # Does the repository contain an action currently or previously listed in the marketplace?
  def action_ever_listed?
    actions.any? { |action| action.listed? || action.delisted? }
  end

  # Returns the global relay id from the given repository id.
  # If the repository was deleted, it falls back to generating a relay id from the repo id.
  # Being replaced by next_global_id
  def self.global_relay_id(repository_id)
    repo = Repositories.domain.by_id(repository_id)

    if repo.nil?
      # If the repository was deleted and purged, generate a fake repo to get a global relay id.
      repo = Repository.instantiate("id" => repository_id)

      if GitHub.enterprise?
        return Platform::Helpers::NodeIdentification.to_legacy_global_id(repo.platform_type_name, repo.global_id)
      else
        # Use the next format since both formats will be accepted on the `launch` side
        return Platform::Helpers::NodeIdentification.async_to_next_global_id(repo).sync
      end
    end

    !GitHub.enterprise? ? repo.next_global_id : repo.global_relay_id
  end

  def actions_app_installation(read_from_primary: false)
    role = read_from_primary ? :writing : :reading
    ActiveRecord::Base.connected_to(role: role) do
      GitHub.launch_github_app&.installations_on(owner)&.with_repository(self)&.first
    end
  end

  # Synchronous wrapper for the async method version #async_show_actions?
  def show_actions?(include_pending_setup: true)
    async_show_actions?(include_pending_setup: include_pending_setup).sync
  end

  # A repository has specific configuration around the state of Actions but there are also some extra rules
  # that make it not as simple as the basic binary yes/no.  The #show_actions? and #async_show_actions?
  # help layer on these extra conditions.  These methods can then be shared among presentation layers, whether
  # it is dotcom's front-end or our mobile applications using GraphQL, to determine ultimately if Actions should
  # be available for a user to see.
  #
  # Arguments:
  # - include_pending_setup: Defaults to true, pass in false if Actions need to be fully configured to be shown.
  #   This is necessary because a splash screen can be shown to assist the user discover the next steps to get
  #   actions functional.   The initial use-case for not including pending setup is for our mobile applications
  #   since configuring Actions is not currently supported on mobile.
  def async_show_actions?(include_pending_setup: true)
    return repository_can_have_actions_on_private_forks? if repo_is_advisory_workspace?

    return Promise.resolve(true) if (GitHub.actions_enabled? && !actions_disabled?) ||
      (include_pending_setup && !GitHub.actions_enabled? && GitHub.actions_packages_enterprise_setup_pending?)

    begin
      if owner.is_a?(Organization)
        Promise.resolve(actions_disabled? && workflows.required.not_deleted.any?)
      else
        Promise.resolve(actions_disabled? && !actions_disabled_by_owner? && workflows.required.not_deleted.any?)
      end
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionFailed => e
      # if the repositories_actions_checks cluster isn't functional, report the error then
      # return false instead of failing the full page load.
      Failbot.report e

      Promise.resolve(false)
    end
  end

  private

  def repo_is_advisory_workspace?
    return false unless GitHub.repository_advisories_enabled?

    advisory_workspace?
  end

  def repository_can_have_actions_on_private_forks?
    return Promise.resolve(false) unless GitHub.actions_enabled?
    return Promise.resolve(false) unless GitHub.repository_advisories_enabled?

    parent_advisory.async_repository.then do |root_repo|
      # we cannot find the parent advisory's repository.
      return Promise.resolve(false) unless root_repo

      # We do not need the owner but we do need it loaded in order to execute the
      # Repository#actions_enabled? method
      root_repo.async_owner.then do
        Promise.resolve(
          root_repo.actions_enabled? &&
          root_repo.feature_flag_enabled?(:maintainer_love_advisory_workspaces_can_use_actions, default: false)
        )
      end
    end
  end

  def can_use_actions_enterprise_features?(allow_legacy_plans: false)
    # Legacy billing plans cannot use Actions features
    GitHub.actions_enabled? && (allow_legacy_plans || self.owner.plan.actions_eligible?) && (self.public? || owner_can_use_actions_enterprise_features?)
  end

  def can_use_actions_team_features?(allow_legacy_plans: false)
    # Legacy billing plans cannot use Actions features
    GitHub.actions_enabled? && (allow_legacy_plans || self.owner.plan.actions_eligible?) && (self.public? || owner_can_use_actions_team_features?)
  end

  def can_use_actions_pro_features?(allow_legacy_plans: false)
    # Legacy billing plans cannot use Actions features
    GitHub.actions_enabled? && (allow_legacy_plans || self.owner.plan.actions_eligible?) && (self.public? || owner_can_use_actions_pro_feature?)
  end

  def can_use_environments_features_on_free_plans?
    return false if GitHub.enterprise? # GHES doesn't have free plans, environments is available via other checks
    GitHub.actions_enabled? && self.owner.plan.actions_eligible?
  end

  # Parse the Action metadata file and return a hash with config
  def get_action_config_from_yml_file(yml_file)
    config = {
      is_action: false,
    }

    begin
      file_data = YAML.safe_load(yml_file.data)
    rescue Psych::Exception
      return config
    end

    return config unless file_data.is_a?(Hash)
    file_data = file_data.with_indifferent_access

    config.update(
      path: yml_file.path,
      is_action: file_data[:name].present?,
      name: file_data[:name],
      description: file_data[:description],
      icon_name: file_data.dig(:branding, :icon),
      color: file_data.dig(:branding, :color),
    )
  end

  def files_changed_on_head_matching_names(filenames)
    head = ref_to_sha(default_branch)
    return [] if head.nil?

    entries = tree_entries(head, nil, recursive: true)[1]
    entries.select do |ent|
      ent.blob? && filenames.include?(ent.name)
    end
  end

  def delist_actions
    actions.each { |action| action.delisted! if action.listed? }
  end
end
