# typed: true
# frozen_string_literal: true

class CreateRepositoryOrchestration < RepositoryOrchestration
  include GitHub::Memoizer
  include Repository::CreatorMethods

  DEFAULT_FAILURE_MESSAGE = "Repository creation failed.".freeze

  class BillingError < StandardError; end

  before_create :lock_retired_namespace # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  validate :can_create_repository?, on: :create

  def skip_repository_id_validation
    true
  end

  def can_create_repository?
    if skip_validation?
      @built_repository = Repository.new(@repo_params)
      return
    else
      @built_repository = Repository.new
    end

    # Here we deactivate the repo so that if it fails to be created from the perspective of spokes, it
    # does not take up an NWO for the owner.
    @built_repository.active = nil

    check_visibility_and_public(@repo_params)

    owner
    owner.enable! if @payment_details.present?

    begin
      @repo_visibility = visibility_from_attributes(@repo_params)
      set_legacy_visibility(@repo_params, @repo_visibility)
    rescue ArgumentError => e
      errors.add(:repository, e.message)
      @allowed = false
      return
    end

    if !creation_allowed?(@repo_visibility, role: @role)
      errors.add(:repository)
      @allowed = false
      return
    end

    if creating_repo_in_personal_namespace_for_emu? || is_enterprise_to_restrict_for_personal_namespace?
      if creating_repo_in_personal_namespace_enterprise_setting_enabled? && creating_repo_in_personal_namespace?
        error_msg = creating_repo_in_personal_namespace_enterprise_setting_message
        errors.add(:repository, error_msg)
        @allowed = false
        return
      end
    end

    if @repo_visibility == Repository::INTERNAL_VISIBILITY
      if !owner.organization?
        errors.add(:repository, "Only organization-owned repositories can have #{Repository::INTERNAL_VISIBILITY} visibility")
      end
      if !owner.business
        errors.add(:repository, "Only organizations associated with an enterprise can set visibility to #{Repository::INTERNAL_VISIBILITY}")
      end
    end

    @allowed_merge_methods = {
      merge_allowed: @repo_params.delete(:allow_merge_commit) { true },
      squash_allowed: @repo_params.delete(:allow_squash_merge) { true },
      rebase_allowed: @repo_params.delete(:allow_rebase_merge) { true },
      auto_merge_allowed: @repo_params.delete(:allow_auto_merge) { false },
      delete_branch_allowed: @repo_params.delete(:delete_branch_on_merge) { false },
      update_branch_allowed: @repo_params.delete(:allow_update_branch) { false },
      squash_pr_title_used_as_default: @repo_params.delete(:use_squash_pr_title_as_default) { false },
      merge_commit_title_setting: @repo_params.delete(:merge_commit_title) { nil },
      merge_commit_message_setting: @repo_params.delete(:merge_commit_message) { nil },
      squash_merge_commit_message_setting: @repo_params.delete(:squash_merge_commit_message) { nil },
      squash_merge_commit_title_setting: @repo_params.delete(:squash_merge_commit_title) { nil },
    }
    begin
      @built_repository.validate_merge_settings_update!(
        merge_allowed: @allowed_merge_methods[:merge_allowed],
        squash_allowed: @allowed_merge_methods[:squash_allowed],
        rebase_allowed: @allowed_merge_methods[:rebase_allowed],
        squash_merge_commit_title_setting: @allowed_merge_methods[:squash_merge_commit_title_setting],
        squash_merge_commit_message_setting: @allowed_merge_methods[:squash_merge_commit_message_setting],
        merge_commit_title_setting: @allowed_merge_methods[:merge_commit_title_setting],
        merge_commit_message_setting: @allowed_merge_methods[:merge_commit_message_setting],
      )
    rescue Repository::PullRequestDependency::MergeMethodError => e
      error_msg = "#{e.message} (#{e.reason})"
      @built_repository.errors.add(:base, error_msg)
      errors.add(:repository, DEFAULT_FAILURE_MESSAGE)
      return
    end

    team_id = @repo_params.delete(:team_id)
    team = team_id && owner.organization? && owner.teams.find_by_id(team_id)
    has_projects = @repo_params.delete(:has_projects)
    @has_discussions = @repo_params.delete(:has_discussions)
    @built_repository.assign_attributes({ owner: owner }.merge(@repo_params))
    @built_repository.created_by_user_id = @user.id
    @built_repository.team_for_after_create = team
    @built_repository.wiki_access_to_pushers = true
    @built_repository.reflog_data = @reflog_data
    current_plan = owner.plan

    if !has_projects.nil?
      begin
        @built_repository.has_projects = has_projects
      rescue Repository::ProjectsSettingsDependency::CannotEnableProjectsError
        if has_projects
          @built_repository.errors.add(:has_projects, "can't be enabled because the owning organization has repository projects disabled.")
          errors.add(:repository, DEFAULT_FAILURE_MESSAGE)
          return
        end
      end
    end

    unless @built_repository.valid?
      owner.assign_attributes(plan: current_plan)
      if @built_repository.errors[:trade_controls_restricted_owner].any?
        message = if owner.organization?
          if owner.adminable_by?(@user)
            ::TradeControls::Notices.organization_account_restricted
          else
            ::TradeControls::Notices.org_restricted
          end
        else
          ::TradeControls::Notices.user_account_restricted
        end.html_safe #rubocop:disable Rails/OutputSafety
        errors.add(:repository, message)
        nil
      elsif @built_repository.errors[:trade_controls_restricted_creator].any?
        message = ::TradeControls::Notices.user_account_restricted.html_safe #rubocop:disable Rails/OutputSafety
        errors.add(:repository, message)
        nil
      elsif @built_repository.errors[:base].first == GitHub::RateLimitedCreation::ERROR_MESSAGE
        error_msg = "You have created too many repositories, too quickly. Please try again later."
        errors.add(:repository, error_msg)
        nil
      else
        billing_error = @built_repository.errors[:visibility].first
        error_msg = billing_error ? "Visibility #{billing_error}" : "Repository creation failed."
        errors.add(:repository, error_msg)
        nil
      end
    end

    if owner.organization? && @custom_properties.present?
      @properties_values_manager = CustomProperties::Public.values_manager(CustomProperties::Public.definitions_manager(owner))
      non_allowed_property_names = @custom_properties.keys.reject do |property|
        @properties_values_manager.repo_creator_can_initialize_property?(@user, property)
      end

      if non_allowed_property_names.empty?
        validation_errors = @properties_values_manager.validate_properties(@custom_properties)

        validation_errors.each { |error| errors.add(:repository, error.error_message) }
      else
        errors.add(:repository, "User does not have permission to set custom properties: #{non_allowed_property_names.join(', ')}")
      end
    end

    if owner.deleted?
      errors.add(:repository, "Owner is being deleted, so new repository cannot be created.")
    end

    validate_creation(@built_repository, @user, @repo_visibility, custom_properties: @custom_properties).each do |error|
      errors.add(:repository, "Due to policy, #{error.first.downcase + error[1..-1]}")
    end
  end

  step :create_repository, max_attempts: 2 do
    return :skipped, "Cannot retry creation." if @built_repository.nil?

    # If the first attempt to create_repository fails outside of the transaction, creation should fail, because
    # we cannot know which after_commit callbacks have succeeded, and what state the repo is in.
    return :failed, "Repository failed creation outside of transaction, and cannot be retried." if Repository.exists?(@built_repository.id)

    if @duplicate_repo_for_retry.nil?
      # On the first attempt, we need to save the original state of the repo, so that we can retry saving it using
      # that original state if the first attempt fails.
      @duplicate_repo_for_retry = @built_repository.dup
    else
      # On attempts beyond the first, we need to reset the built_repository to its original state, to avoid
      # saving the repo using state which was modified on the @built_repository instance, but not committed to the
      # database.
      @built_repository = @duplicate_repo_for_retry.dup
    end

    Repository.transaction do
      if @repo_visibility == Repository::INTERNAL_VISIBILITY
        @built_repository.internal_repository = InternalRepository.new(repository: @built_repository, business: owner.business)
        @built_repository.internal_repository.business = owner.business
        @built_repository.public = false
      end
      @built_repository.skip_after_create_callbacks = true
      @built_repository.expected_creation = true
      @built_repository.save!

      @built_repository.update!(has_wiki: false) if @built_repository.has_wiki? && !@built_repository.plan_supports?(:wikis)
    end
    self.update!(repository: @built_repository)

    # When the transaction encounters a deadlock, there have been cases where the repository is not committed
    # to the database, but no error is raised. So here we double check if the repository exists, and fail fast
    # if it does not. See https://github.com/github/repos/issues/5216.
    if !Repository.exists?(@built_repository.id)
      details = {
        "gh.repo.id" => @built_repository.id,
        "gh.repo.visibility" => @built_repository.visibility,
        "gh.request_id" => GitHub.context[:request_id]
      }
      GitHub.logger.info("Repo creation deadlock", details)
      return :failed, "Repository creation failed."
    end
  rescue ActiveRecord::RecordNotUnique => e
    # Repository should be set to nil, so that saving orchestration does not try to re-save repo
    self.repository = nil
    @built_repository.errors.add :name, "already exists on this account"
    return :skipped, "Repository creation failed."
  rescue ActiveRecord::RecordInvalid => e
    self.repository = nil
    return :skipped, "Repository creation failed."
  ensure
    # Regardless of success or failure we want to release the RepositoryOwnerLock so
    # as not to cause unintended problems.
    unlock_retired_namespace
  end

  step :instrument_dogstats do
    instrument(repository, @repo_params)
  end

  step :add_members_with_default_repository_permissions do
    @built_repository.add_members_with_default_repository_permissions
  end

  step :update_config_entries, max_attempts: 2 do
    ApplicationRecord::Domain::ConfigurationEntries.transaction do
      @built_repository.set_default_workflow_permissions_for_new_repos

      if @has_discussions
        @built_repository.turn_on_discussions(actor: @user, force: true, instrument: false)
      end

      if @built_repository.eligible_for_tiered_reporting?
        @built_repository.enable_tiered_reporting(actor: @user, instrument: false)
      end

      if @allowed_merge_methods
        @built_repository.update_merge_settings(@user, **@allowed_merge_methods, validate_settings: false)
      end
    end
  end

  step :update_abilities do
    if @built_repository.advisory_workspace?
      @built_repository.setup_workspace_abilities(@user)
    elsif owner.organization? && !@built_repository.adminable_by?(@user)
      # We use add_member_without_validation_or_notifications instead of
      # add_member here because we don't want to send the creator an email.
      if @user.user?
        @built_repository.add_member_without_validation_or_notifications(@user, action: :admin)
      end
      response = GitHub.newsies.auto_subscribe(@user,  @built_repository)
      if response.failed?
        GitHub.newsies.async_auto_subscribe(@user, [@built_repository.id])
      end
    end
  end

  step :create_repository_in_spokes do
    created = repository_after_create.create_repository_in_spokes(source_repository:, skip_source_repo_on_clone: data[:skip_source_repo_on_clone])
    if !created
      return :failed, "Repository creation failed."
    end
  end

  step :add_custom_properties do
    @properties_values_manager.set_properties_for([repository], @custom_properties, actor: @user) if @properties_values_manager
  end

  step :activate_repository do
    if owner.reload.deleted?
      repository_after_create.errors.add :owner, "is deleted"
      return :skipped, "Repository creation failed."
    end
    # Activate the repository now that we know it has been created successfully in spokes
    repository_after_create.update!(active: true)
  rescue ActiveRecord::RecordNotUnique => e
    repository_after_create.errors.add :name, "already exists on this account"
    return :skipped, "Repository creation failed."
  rescue ActiveRecord::RecordInvalid => e
    return :skipped, "Repository creation failed."
  end

  step :calculate_network_counts do
    repository_after_create.calculate_network_counts!
  end

  step :enqueue_repo_sponsorables_job_for_sponsorable_owner do
    return unless GitHub.sponsors_enabled?

    repository_after_create.enqueue_repo_sponsorables_job_for_sponsorable_owner
  end

  step :alert_sponsors_listing_has_public_non_fork_repository do
    return unless GitHub.sponsors_enabled?

    repository_after_create.alert_sponsors_listing_has_public_non_fork_repository
  end

  step :auto_subscribe_owners do
    repository_after_create.auto_subscribe_owners
  end

  step :synchronize_search_index do
    repository_after_create.synchronize_search_index
  end

  step :add_repository_to_team do
    repository_after_create.add_repository_to_team
  end

  step :setup_security_products do
    repository_after_create.setup_security_products_on_creation(@user, false)
  end

  step :instrument_creation do
    repository_after_create.instrument_creation
  end

  step :reset_memoized_attributes do
    repository_after_create.reset_memoized_attributes
  end

  step :instrument_for_blackbird_search do
    payload = {
      change: :CREATED,
      repository: repository,
      owner_name: repository_after_create.owner&.name,
      updated_at: Time.now.utc,
      ref: "refs/heads/#{repository_after_create.default_branch}",
    }

    GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
    GitHub.dogstats.increment("geyser.repo_changed_event.published", tags: ["change_type:created"])
  end

  step :install_current_integration_on_repository do
    return unless @current_integration_context

    installation, editor =
      if @user.bot?
        [@user.installation, @user.installation]
      else
        [@current_integration_context[:integration].installations_on(owner).first, @user]
      end

    if installation.installed_on_selected_repositories?
      IntegrationInstallation::RepositoryEditor.perform(
        installation,
        action: :add_from_api,
        repositories: [repository],
        editor: editor,
        entry_point: @current_integration_context[:entry_point]
      )
    end
  end

  job_start

  # Be careful about placing a step between this and the job_start method above.
  # The orchestration keeps track of what the immediate next step after job_start is called in a persisted manner,
  # and changing the expected value to a new step can cause the orchestration to fail.
  step :instrument_repo_added_to_installations_across_all_repositories_async do
    repository_after_create.instrument_repo_added_to_installations_across_all_repositories
  end

  step :publish_workspace_created do
    return unless repository_after_create.parent_advisory.present?

    user = User.find_by(id: data[:actor_id])
    return unless GitHub.flipper[:advisory_db_unrestorable_repositories].enabled?(repository_after_create.parent_advisory&.repository) || GitHub.flipper[:advisory_db_unrestorable_repositories].enabled?(user)

    message = build_hydro_event_message.merge({
      actor_id: user&.id,
      advisory_id: repository_after_create.parent_advisory&.id,
    })

    publish_hydro_event(message: message, schema: "github.repositories.v1.WorkspaceCreated")
  end

  step :publish_created do
    message = self.class.build_hydro_event_message_from_repository(repository, actor_id: data[:actor_id])
    publish_hydro_event(message: message, schema: "github.repositories.v1.Created")
  end

  step :enqueue_copy_language_stats_job do
    copy_from_repo_id = data[:source_repository_id]

    if repository_after_create.advisory_workspace?
      repository_after_create.parent_advisory_repository.id
    end

    if copy_from_repo_id
      RepositoryCopyLanguageStatsJob.perform_later(repository_after_create.id, copy_from_repo_id:)
    end
  end

  step :delete_redirect_repository do
    redirect = RepositoryRedirect.find_by(repository_name: repository_after_create.name_with_display_owner)
    return unless redirect

    redirect.destroy!
  end

  def self.build_hydro_event_message_from_repository(repository, actor_id: nil)
    return unless repository.present?

    message = build_hydro_event_message(repository.id).merge({
      repository: Hydro::EntitySerializer.repository(repository)
    })
    if actor_id
      message = message.merge({ actor_id: actor_id })
    end

    message
  end

  def only_save_on_orchestration_end?
    true
  rescue ArgumentError
    false
  end

  def skip_validation?
    @skip_validation
  end

  attr_reader :result
  attr_reader :allowed
  attr_reader :built_repository

  attr_writer :owner_login
  attr_writer :user
  attr_writer :repo_params
  attr_writer :reflog_data
  attr_writer :custom_properties
  attr_writer :payment_details
  attr_writer :template_hook_failure
  attr_writer :role
  attr_writer :skip_validation
  attr_writer :current_integration_context

  protected

  def target_uniqueness_condition_on_start
    # We can't evaluate uniqueness when starting the orchestration as the repository is not created yet
  end

  sig { returns(T.nilable(Repository)) }
  memoize def source_repository
    Repository.find_by(id: data[:source_repository_id])
  end

  sig { returns(Repository) }
  memoize def repository_after_create
    T.must(repository)
  end
end
