# typed: true
# frozen_string_literal: true

class EditRepositoriesController < AbstractRepositoryController
  include Repos::RulesHelper

  map_to_service :branch_protection_rule, only: [:branches, :update_default_branch, :ruleset_new, :ruleset_destroy, :ruleset_show, :ruleset_index, :rule_insights, :ruleset_validate_value, :ruleset_update, :rule_insights_actors, :ruleset_bypass_suggestions, :status_check_suggestions, :ruleset_integration_suggestions, :deployment_environment_suggestions, :ruleset_history_comparison, :ruleset_history_view, :export_ruleset, :ruleset_history_summary, :merge_queue_merge_methods, :ruleset_required_reviewer_suggestions, :ruleset_deferred_target_counts, :ruleset_validate_import, :request_bypass] # rubocop:todo GitHub/MapToService
  include SecurityAnalysisSettingsHelper
  include ControllerMethods::SecurityAnalysisSettings
  include EditRepositoriesHelper
  include BranchesHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Orgs::CustomPropertiesHelper

  include RulesetViewControllerMethods
  include RulesetEditControllerMethods
  include RulesetInsightsControllerMethods

  allow_verified_fetch only: [:ruleset_update, :ruleset_destroy, :ruleset_validate_value, :ruleset_validate_import, :ruleset_integration_suggestions, :status_check_suggestions, :transfer, :transfer_team_suggestions, :abort_transfer, :ruleset_history_comparison, :ruleset_deferred_target_counts, :ruleset_required_reviewer_suggestions, :request_bypass]

  sig { override.returns(RuleEngine::Types::RuleSource) }
  protected def current_source
    current_repository
  end

  sig { override.returns(String) }
  protected def index_path
    repository_rulesets_path
  end

  sig { override.returns(Symbol) }
  protected def selected_link
    :repo_rulesets
  end

  sig { override.returns(Symbol) }
  protected def selected_insights_link
    :repo_rule_insights
  end

  sig { override.returns(T::Array[String]) }
  protected def supported_targets
    %w[branch tag push]
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    only: [:options]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:access]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:branches]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:keys, :new_key]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:member_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:abuse_reporters]

  # Added in addition to those depended on in the shared ruleset controller methods
  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:ruleset_new, :ruleset_index, :ruleset_show, :rule_insights, :ruleset_history_comparison, :ruleset_history_view]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Iam,
    only: [:reported_content]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    optional: true,
    only: [:options, :branches, :reported_content, :keys, :access, :new_key, :abuse_reporters]

  REPORTED_CONTENT_PER_PAGE = 50
  TEAM_SUGGESTIONS_PAGE_SIZE = 10

  skip_before_action :cap_pagination, unless: :robot?

  skip_before_action :privacy_check, only: [:update_topics, :update_meta]

  before_action :login_required
  before_action :non_migrating_repository_required,
    only: [:detach, :transfer, :set_visibility, :unarchive, :remove_member]
  before_action :writable_repository_required,
    except: [:access, :delete, :detach, :keys, :options, :tabs, :transfer, :set_visibility, :unarchive, :remove_member]
  before_action :metadata_permissions_required, only: :update_meta
  before_action :custom_tabs_only, only: [:tabs, :add_tab, :remove_tab]
  before_action :manage_topics_permissions_required, only: [:update_topics]
  before_action :wiki_settings_permissions_required, only: [:update_wiki_settings, :update_wiki_access]
  before_action :toggle_merge_types_permissions_required, only: :update_merge_settings
  before_action :projects_settings_permissions_required, only: :toggle_projects
  before_action :allowed_repo_criteria, only: [:update_wiki_settings]
  before_action do
    T.bind(self, EditRepositoriesController)
    render "repositories/states/trade_controls_read_only" if current_repository.trade_controls_read_only?
  end
  before_action :add_spamurai_form_signals, only: [:update, :rename]
  before_action :parse_json_params, only: [:transfer]

  before_action :sudo_filter, only: %i(
    add_team
    access
    delete
    detach
    set_visibility
    transfer
    update_member
    change_anonymous_git_access
  )

  RULESET_ROUTES = [
    :ruleset_validate_value,
    :ruleset_bypass_suggestions,
    :export_ruleset,
    :ruleset_index,
    :rule_insights,
    :rule_insights_actors,
    :ruleset_new,
    :ruleset_show,
    :ruleset_destroy,
    :ruleset_update,
    :ruleset_deferred_target_counts,
    :ruleset_integration_suggestions,
    :ruleset_required_reviewer_suggestions,
    :status_check_suggestions,
    :ruleset_history_comparison,
    :ruleset_history_view,
    :deployment_environment_suggestions,
  ]

  before_action :ensure_admin_access, except: [
    :options,
    :update_meta,
    :branches,
    :update_topics,
    :update_wiki_settings,
    :update_wiki_access,
    :update_merge_settings,
    :update_issue_settings,
    :toggle_projects,
    :keys,
    :new_key,
  ].concat(RULESET_ROUTES)

  # Currently edit permission is required to even load the branches tab.
  before_action :ensure_user_has_edit_branch_protection, only: [:branches].concat(RULESET_ROUTES)

  before_action :ensure_user_can_manage_deploy_keys, only: [:keys, :new_key]

  before_action :plan_supports_enterprise_rulesets, only: [
    :rule_insights,
    :rule_insights_actors,
    :ruleset_history_comparison,
    :ruleset_history_summary,
    :ruleset_history_view,
  ]

  preload_features [:custom_roles], only: :access

  after_action :enqueue_sync_package_access_job, only: [:add_team, :remove_team]

  layout "repository"
  javascript_bundle :settings
  stylesheet_bundle :settings
  stylesheet_bundle :suggestions

  def options # rubocop:todo GitHub/UseRestfulActions
    permission = current_repository.async_action_or_role_level_for(current_user).sync

    # Show the classic settings page for users with Admin permission,
    # but show FGP options for those with the Maintain role etc.
    if permission == :admin
      render "edit_repositories/pages/options", locals: {
        permission: permission,
        heads_count: current_repository.heads.size,
      }
    else
      return render_404 unless fgp_options_page_viewable?
      render "edit_repositories/pages/fgp_options", locals: {
        permission: permission,
        current_repository: current_repository,
        current_user: current_user,
      }
    end
  end

  def access # rubocop:todo GitHub/UseRestfulActions
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal, attributes: {
      GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/roles_and_permissions" }) do

      @selected_link = :collaborators

      query = params[:query]
      filter = params.fetch(:filter, :all).to_sym
      before = params[:before]
      after = params[:after]
      limit = params[:limit]
      direct_access_list = ::RepositoryAccessList.new(
        repository: current_repository, current_user:, query:, filter:, before:, after:, limit:
      )

      repository_roles = ::RepositoryMemberRoles.fetch(
        repository:   current_repository,
        current_user: current_user,
        members:      direct_access_list.user_results,
        teams:        direct_access_list.repository_teams,
      )

      if current_repository.owner.is_a?(::Organization)
        organization_wide_access_list = current_repository.owner.highest_all_repo_access_by_actor_type
      end

      respond_to do |format|
        format.html do
          if request&.xhr? && (!pjax? || pjax_container == "#repository-access-table")
            selected_members =
              if current_repository.in_organization?
                current_repository.organization.visible_users_for(current_user, actor_ids: params[:member_ids] || [])
              else
                selected_members_for_user_repo
              end
            return render partial: "edit_repositories/admin_screen/access_management/members_table_body",
              locals: {
                view: create_view_model(
                  EditRepositories::Pages::ManagedAccessPageView,
                  repository: current_repository,
                  page: current_page,
                  repository_roles:,
                  selected_members:,
                  direct_access_list:,
                  organization_wide_access_list:,
                )
              }
          else
            view = create_view_model(
              EditRepositories::Pages::ManagedAccessPageView,
              repository: current_repository,
              page: current_page,
              repository_roles:,
              direct_access_list:,
              organization_wide_access_list:,
            )
            render "edit_repositories/pages/managed_access", locals: { view: view }
          end
        end
      end
    end
  end

  def member_suggestions # rubocop:todo GitHub/UseRestfulActions
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal, attributes: {
      GitHub::TaggingHelper::CATALOG_SERVICE_TAG => "github/roles_and_permissions" }) do

      respond_to do |format|
        format.html_fragment do
          render partial: "edit_repositories/admin_screen/access_management/member_suggestions",
          formats: :html,
          locals: {
            view: create_view_model(EditRepositories::AdminScreen::MemberSuggestionsView,
              organization: current_repository.organization,
              include_teams: true,
              repository: current_repository,
              query: params[:q],
              add_type: params[:add_type],
            )
          }
        end
        format.html do
          render partial: "edit_repositories/admin_screen/access_management/member_suggestions",
          formats: :html,
          locals: {
            view: create_view_model(EditRepositories::AdminScreen::MemberSuggestionsView,
              organization: current_repository.organization,
              include_teams: true,
              repository: current_repository,
              query: params[:q],
              add_type: params[:add_type],
            )
          }
        end
      end
    end
  end

  BRANCHES_PAGE_SIZE = 100

  def branches # rubocop:todo GitHub/UseRestfulActions
    branch_protection_rules = current_repository.protected_branches
                              .order(id: :asc)
                              .paginate(page: current_page, per_page: BRANCHES_PAGE_SIZE)

    matches_ref_counts_by_rule = {}
    unless current_repository.heads.size > ProtectedBranch::MAX_BRANCHES_TO_CALCULATE_MATCHES
      Promise.all(branch_protection_rules.map do |rule|
        Platform::Loaders::BranchProtectionRule::MatchesAndConflicts.load(current_repository, rule).then do |information|
          matches_ref_counts_by_rule[rule] = information[:matches].size
        end
      end).sync
    end

    render "branch_protection_rules/index", locals: {
      branch_protection_rules: branch_protection_rules,
      matches_ref_counts_by_rule: matches_ref_counts_by_rule,
      heads_count: current_repository.heads.size,
    }
  end

  def keys # rubocop:todo GitHub/UseRestfulActions
    @public_key = current_repository.public_keys.find_by_id(params[:id])

    page = params[:page].to_i
    page = 1 unless page > 0 # to_i defaults to 0 for invalid inputs, also catches negative numbers
    page_size = params[:page_size].to_i
    page_size = 20 unless page_size > 0

    keys = current_repository.public_keys.paginate(
      page: page,
      per_page: page_size,
    )

    deploy_keys_disabled, deploy_keys_disabled_by = current_repository.deploy_keys_disabled_by_policy_with_policy_source
    render "edit_repositories/pages/deploy_keys",
      locals: {
        keys: keys,
        total_keys: current_repository.public_keys.count,
        deploy_keys_disabled: deploy_keys_disabled,
        deploy_keys_disabled_by: deploy_keys_disabled_by,
      }
  end

  def new_key # rubocop:todo GitHub/UseRestfulActions
    deploy_keys_disabled, _ = current_repository.deploy_keys_disabled_by_policy_with_policy_source
    if deploy_keys_disabled
      flash[:error] = "Deploy keys are disabled for this repository."
      return redirect_to repository_keys_path(current_repository.owner, current_repository)
    end
    render "edit_repositories/pages/new_key"
  end

  def url(suffix, options = nil) # rubocop:todo GitHub/UseRestfulActions
    "#{GitHub.api_url}#{suffix}"
  end

  def status_check_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      query = params.require(:query)

      format.json do
        render json: RulesEngine::Suggestions.recent_status_checks_for(current_repository, query, limit: 10)
      end
    end
  end

  def deployment_environment_suggestions  # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      query = params.require(:query)
      format.json do

        render json: RulesEngine::Suggestions.deployment_environments_for(current_repository, query)
      end
    end
  end

  def merge_queue_merge_methods  # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: RulesEngine::Suggestions.merge_queue_merge_methods_for(current_repository)
      end
    end
  end

  def update_merge_settings # rubocop:todo GitHub/UseRestfulActions
    merge_types = Array(params[:merge_types])
    squash_selected = merge_types.include?("squash_merge")
    merge_selected = merge_types.include?("merge_commit")
    rebase_selected = merge_types.include?("rebase_merge")
    auto_merge_selected = merge_types.include?("auto_merge")
    delete_branch_selected = merge_types.include?("delete_branch")
    update_branch_selected = merge_types.include?("update_branch")

    squash_merge_commit_types = Array(params[:squash_merge_commit_types])
    if squash_merge_commit_types.include?("use_squash_pr_body_as_default")
      squash_pr_title_selected = Configurable::SquashMergeCommitTitle::PR_TITLE
      squash_pr_body_selected = Configurable::SquashMergeCommitMessage::PR_BODY
    elsif squash_merge_commit_types.include?("use_squash_pr_title_as_default")
      squash_pr_title_selected = Configurable::SquashMergeCommitTitle::PR_TITLE
      squash_pr_body_selected = Configurable::SquashMergeCommitMessage::BLANK
    elsif squash_merge_commit_types.include?("use_squash_pr_commits_as_default")
      squash_pr_title_selected = Configurable::SquashMergeCommitTitle::PR_TITLE
      squash_pr_body_selected = Configurable::SquashMergeCommitMessage::COMMIT_MESSAGES
    elsif squash_merge_commit_types.include?("use_default_squash_title_and_body")
      squash_pr_title_selected = Configurable::SquashMergeCommitTitle::COMMIT_OR_PR_TITLE
      squash_pr_body_selected = Configurable::SquashMergeCommitMessage::COMMIT_MESSAGES
    end

    merge_commit_types = Array(params[:merge_commit_types])
    if merge_commit_types.include?("use_merge_pr_body_as_default")
      merge_pr_title_selected = Configurable::MergeCommitTitle::PR_TITLE
      merge_pr_body_selected = Configurable::MergeCommitMessage::PR_BODY
    elsif merge_commit_types.include?("use_merge_pr_title_as_default")
      merge_pr_title_selected = Configurable::MergeCommitTitle::PR_TITLE
      merge_pr_body_selected = Configurable::MergeCommitMessage::BLANK
    elsif merge_commit_types.include?("use_default_merge_title_and_body")
      merge_pr_title_selected = Configurable::MergeCommitTitle::MERGE_MESSAGE
      merge_pr_body_selected = Configurable::MergeCommitMessage::PR_TITLE
    end

    begin
      current_repository.update_merge_settings(current_user,
        rebase_allowed: rebase_selected,
        merge_allowed: merge_selected,
        squash_allowed: squash_selected,
        auto_merge_allowed: auto_merge_selected,
        delete_branch_allowed: delete_branch_selected,
        update_branch_allowed: update_branch_selected,
        squash_pr_title_used_as_default: squash_pr_title_selected,
        squash_merge_commit_title_setting: squash_pr_title_selected,
        squash_merge_commit_message_setting: squash_pr_body_selected,
        merge_commit_title_setting: merge_pr_title_selected,
        merge_commit_message_setting: merge_pr_body_selected
      )
    rescue Repository::PullRequestDependency::MergeMethodError => e
      if request&.xhr?
        return render status: 422, plain: "#{e.message} (#{e.reason})"
      else
        flash[:error] = e.message
        return redirect_to :back
      end
    end

    if request&.xhr?
      head 200
    else
      flash[:notice] = "Repository settings saved."
      redirect_to :back
    end
  end

  def update_branch_protection_settings # rubocop:todo GitHub/UseRestfulActions
    branch_protection_disabled = ActiveModel::Type::Boolean.new.cast(params[:branch_protection_disabled])

    begin
      unless branch_protection_disabled.nil?
        if branch_protection_disabled
          BranchProtectionsConfig.new(current_repository).disable_branch_protection(actor: T.must(current_user))
        else
          BranchProtectionsConfig.new(current_repository).enable_branch_protection(actor: T.must(current_user))
        end
      end
    rescue Repository::PullRequestDependency::MergeMethodError => e
      if request&.xhr?
        return render status: 422, plain: "#{e.message} (#{e.reason})"
      else
        flash[:error] = e.message
        return redirect_to :back
      end
    end

    if request&.xhr?
      head 200
    else
      flash[:notice] = "Branch protection settings saved."
      redirect_to :back
    end
  end

  def update_archive_settings # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless can_enable_lfs_in_archives?

    success = if params[:include_lfs_objects] == "1"
      current_repository.enable_lfs_in_archives(current_user)
    else
      current_repository.disable_lfs_in_archives(current_user)
    end

    unless success
      flash[:error] = "Archive settings could not be toggled at this time."
      return redirect_to(edit_repository_path(current_repository))
    end

    handle_request_response(edit_repository_path(current_repository))
  end

  def update_push_settings # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.plan_supports?(:protected_branches)

    begin
      enabled = params[:enable_max_pushes] == "true"
      value = begin
        Integer(params[:max_pushes_count])
      rescue ArgumentError
        -1 # -1 will raise a useful error message for users when we call set_max_ref_updates()
      end

      if enabled
        if value == 0 then value = -1 end # Not valid to set enabled but set limit to zero
        current_repository.set_max_ref_updates(value, current_user)
      else
        current_repository.set_max_ref_updates(0, current_user)
      end

    rescue ArgumentError => e
      if request&.xhr?
        return render status: 422, plain: e.message
      else
        flash[:error] = e.message
        return redirect_to :back
      end
    end

    if request&.xhr?
      head 200
    else
      flash[:notice] = "Repository settings saved."
      redirect_to :back
    end
  end

  def update_wiki_settings # rubocop:todo GitHub/UseRestfulActions
    current_repository.update(has_wiki: params[:has_wiki])

    if request&.xhr? && current_repository.errors.any?
      return render status: 422, plain: "Error saving your changes: #{current_repository.errors.full_messages.to_sentence}"
    end

    handle_request_response(edit_repository_path(current_repository))
  end

  def update_wiki_access # rubocop:todo GitHub/UseRestfulActions
    current_repository.update(wiki_access_to_pushers: params[:wiki_access_to_pushers])

    if request&.xhr? && current_repository.errors.any?
      return render status: 422, plain: "Error saving your changes: #{current_repository.errors.full_messages.to_sentence}"
    end

    handle_request_response(edit_repository_path(current_repository))
  end

  def update_issue_settings # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.has_issues?

    if params[:auto_close_issues] == "1"
      AutoCloseIssuesConfig.new(current_repository).allow_auto_close(actor: current_user)
    elsif params[:auto_close_issues] == "0"
      AutoCloseIssuesConfig.new(current_repository).disallow_auto_close(actor: current_user)
    end

    if request&.xhr? && current_repository.errors.any?
      return render status: 422, plain: "Error saving your changes: #{current_repository.errors.full_messages.to_sentence}"
    end

    handle_request_response(edit_repository_path(current_repository))
  end

  def update_release_settings # rubocop:todo GitHub/UseRestfulActions
    immutable_releases_config = Releases::ImmutableRepositoryConfig.new(current_repository)

    if params[:release_immutability] == "1"
      immutable_releases_config.enable_immutable_releases(actor: current_user)
    elsif params[:release_immutability] == "0"
      immutable_releases_config.disable_immutable_releases(actor: current_user)
    end

    handle_request_response(edit_repository_path(current_repository))
  end

  def toggle_projects # rubocop:todo GitHub/UseRestfulActions
    memex_projects_enabled = params[:memex_projects_enabled]
    projects_enabled = params[:projects_enabled]

    unless projects_enabled.nil?
      if projects_enabled == "1"
        current_repository.enable_repository_projects(actor: current_user)
      else
        current_repository.disable_repository_projects(actor: current_user)
      end
    end

    unless memex_projects_enabled.nil?
      if memex_projects_enabled == "1"
        current_repository.enable_repository_memex_projects(actor: current_user)
      else
        current_repository.disable_repository_memex_projects(actor: current_user)
      end
    end

    if request&.xhr? && current_repository.errors.any?
      return render status: 422, plain: "Error saving your changes: #{current_repository.errors.full_messages.to_sentence}"
    end

    handle_request_response(edit_repository_path(current_repository))

  rescue Repository::ProjectsDependency::CannotEnableProjectsError
    # The UI blocks this path from being hit, but just in case someone
    # tries to hack past the UI restriction, this avoids a 500 and gives
    # a helpful error message.
    error_message = "Projects cannot be enabled when the owning organization has projects disabled."

    if request&.xhr?
      render status: 422, plain: error_message
    else
      flash[:error] = error_message
      redirect_to :back
    end
  end

  def update_dco_settings # rubocop:todo GitHub/UseRestfulActions
    # Don't allow to change this setting if the value is overridden by the org
    return render_404 if current_repository.owner&.organization? && current_repository.owner.dco_signoff_enabled?

    dco_signoff_enabled = params[:enable_dco_signoff] == "1"
    if dco_signoff_enabled
      current_repository.enable_dco_signoff(actor: current_user)
    else
      current_repository.reset_dco_signoff(actor: current_user)
    end

    handle_request_response(edit_repository_path(current_repository))
  end

  # Are you adding a new checkbox to the repo settings page?
  # Avoid adding it to this method; create a new endpoint, instead.
  # See https://github.com/github/github/pull/144368 for an example.
  def update
    Repository.transaction do
      ApplicationRecord::Domain::ConfigurationEntries.transaction do

        # some feature settings are attributes on Repository
        has_params = params.slice(:has_wiki,
                                  :has_issues,
                                  :wiki_access_to_pushers,
                                  :template).permit!

        current_repository.update!(has_params)

        if current_repository.can_participate_in_archive_program?
          if params[:archive_program_opt_out_enabled] == "1"
            current_repository.enable_archive_program_opt_out(actor: current_user)
          elsif params[:archive_program_opt_out_enabled] == "0"
            current_repository.disable_archive_program_opt_out(actor: current_user)
          end
        end

        if params[:projects_enabled] == "1"
          current_repository.enable_repository_projects(actor: current_user)
        elsif params[:projects_enabled] == "0"
          current_repository.disable_repository_projects(actor: current_user)
        end

        if current_repository.private_repository_forking_configurable? && !current_repository.allow_private_repository_forking_disabled_by_inherited_policy?
          if params[:allow_private_repository_forking] == "1"
            current_repository.allow_private_repository_forking(actor: current_user)
          elsif params[:allow_private_repository_forking] == "0"
            current_repository.block_private_repository_forking(actor: current_user)
          end
        end

        if current_repository.can_enable_repository_funding_links?
          if params[:enable_repository_funding_links] == "1"
            current_repository.enable_repository_funding_links(actor: current_user)
          elsif params[:enable_repository_funding_links] == "0"
            current_repository.disable_repository_funding_links(actor: current_user)
          end
        end
      end
    end

    handle_request_response
  rescue Repository::ProjectsDependency::CannotEnableProjectsError
    # The UI blocks this path from being hit, but just in case someone
    # tries to hack past the UI restriction, this avoids a 500 and gives
    # a helpful error message.
    flash[:error] = "Projects cannot be enabled when the owning organization has projects disabled."
    redirect_to :back
  end

  param_encoding :update_default_branch, :name, "ASCII-8BIT"

  def update_default_branch # rubocop:todo GitHub/UseRestfulActions
    if current_repository.default_branch == params[:name]
      flash[:error] = "Default branch is already #{params[:name]}"
    elsif current_repository.switch_default_branch(current_user, params[:name])
      flash[:notice] = "Default branch changed to #{params[:name]}"
    else
      flash[:error] = "Could not change default branch"
    end
    redirect_to :back
  end

  # Update the metadata for this repo. Is invoked via the 'Save Changes' button.
  def update_meta # rubocop:todo GitHub/UseRestfulActions
    update_params = {
      description: params[:repo_description],
      homepage: params[:repo_homepage],
    }

    if params[:repo_sections].present?
      current_repository.update_sidebar_section_visibility(params[:repo_sections], actor: current_user)
    end

    update_topics_ok = if topics = params[:repo_topics]&.reject(&:empty?)
      current_repository.update_topics(topics, user: current_user)
    else
      true
    end

    current_repository.validate_description_length = true

    if update_topics_ok && current_repository.update(update_params)
      current_repository.invalidate_nwo_cache(Repositories::Cache::InvalidateOn::WebMutation)

      respond_to do |format|
        format.html do
          flash[:notice] = "Your repository details have been saved."
          redirect_to :back
        end
      end
    else
      flash[:error] = "Error saving your changes: #{current_repository.errors.full_messages.to_sentence}"
      redirect_to :back
    end
  end

  # Update the topics for this repo. It is invoked via AJAX when the user enters a new
  # topic.
  def update_topics # rubocop:todo GitHub/UseRestfulActions
    unless params[:repo_topics]
      return head :ok if request&.xhr?
      return redirect_to :back
    end

    topics = params[:repo_topics].reject { |name| name.blank? }

    unless current_repository.update_topics(topics, user: current_user)
      if current_repository.invalid_topic_names.any?
        error_message = current_repository.errors[:repository_topics].join(", ")
        invalid_topics = current_repository.invalid_topic_names
      else
        error_message = "Could not apply the given topics at this time."
      end

      if request&.xhr?
        if invalid_topics.present?
          return render json: {
            invalidTopics: invalid_topics,
            message: error_message,
          }, status: :unprocessable_entity
        end

        return head :unprocessable_entity
      end

      flash[:error] = error_message
    end

    return head :ok if request&.xhr?
    redirect_to :back
  end

  def request_bypass # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.repo_policy_bypass_enabled?

    allowed_action_types = %w[change_visibility delete]

    return flash.now[:error] = "Invalid action" unless allowed_action_types.include?(params[:action_type])

    operation_hash = T.let(T.must(
      case params[:action_type]
      when "change_visibility"
        return flash.now[:error] = "No visibility specified" if params[:new_visibility].nil?
        { change_visibility: params[:new_visibility] }
      when "delete"
        { delete: nil }
      end
    ), T::Hash[Symbol, T.untyped])

    request_type = Exemptions::Evaluators::RepositoryPolicyRulesetBypass.request_type

    # See if there's an existing bypass request and redirect to it if found
    existing_rule_event = RuleEngine::EventActionRepositoryOperation.find_by(
      repository: current_repository,
      operation: params[:action_type].to_sym
    )
    if existing_rule_event && existing_rule_event.rule_suite
      existing_request = RuleEngine::BypassDelegation.existing_ruleset_request(
        T.must(existing_rule_event.rule_suite),
        T.must(current_user),
        request_type
      )
      return redirect_to existing_request.permalink if existing_request
    end

    begin
      rule_suite = RulesEngine::RepositoryActionEvaluator.evaluate_operation(current_repository, T.must(current_user), operation_hash, persist_results: true)
      raise "Failed to create bypass request" unless rule_suite.present?

      message = params[:bypass_request_message]
      new_request = RuleEngine::BypassDelegation.create_ruleset_request!(rule_suite, T.must(current_user), request_type, message)
      redirect_to new_request.permalink
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:error] = e.message
    end
  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    unless repo_name_verification_valid?(params[:verify])
      flash[:error] = "You must type the name of the repository to confirm."
      return redirect_to edit_repository_path(current_repository)
    end

    error = current_repository.cannot_delete_repository_reason(current_user)
    case error
    when :ofac_trade_restricted
      if current_repository.trade_controls_read_only? || current_repository.plan_owner.organization?
        flash[:trade_controls_organization_billing_error] = true
      else
        flash[:trade_controls_user_billing_error] = true
      end
      return redirect_to edit_repository_path(current_repository)
    when :cant_delete_repos_on_this_appliance
      flash[:error] = "Users cannot delete repositories on this appliance."
      return redirect_to edit_repository_path(current_repository)
    when :members_cant_delete_repositories
      flash[:error] = "Organization members cannot delete repositories."
      return redirect_to edit_repository_path(current_repository)
    when :not_ready_for_writes
      flash[:error] = "Repository cannot be deleted until it is done being created on disk."
      return redirect_to edit_repository_path(current_repository)
    when :prevented_by_ruleset
      flash[:error] = "Ruleset(s) are preventing this repository from being deleted."
      return redirect_to edit_repository_path(current_repository)
    end

    if is_codespace_dotfiles_repo?(current_user, current_repository)
      T.must(current_user).disable_codespace_dotfiles(actor: current_user)
    end

    current_repository.remove(current_user)
    flash[:notice] = "Your repository \"#{current_repository.name_with_display_owner}\" was successfully deleted."
    redirect_to user_or_org_repos_path
  end

  def archive # rubocop:todo GitHub/UseRestfulActions
    unless repo_name_verification_valid?(params[:verify])
      flash[:error] = "You must type the name of the repository to confirm."
      return redirect_to edit_repository_path(current_repository)
    end

    current_repository.set_archived
    flash[:notice] = "Your repository \"#{current_repository.name_with_display_owner}\" was successfully archived."
    redirect_to :back
  end

  def unarchive # rubocop:todo GitHub/UseRestfulActions
    unless repo_name_verification_valid?(params[:verify])
      flash[:error] = "You must type the name of the repository to confirm."
      return redirect_to edit_repository_path(current_repository)
    end

    current_repository.unset_archived
    flash[:notice] = "Your repository \"#{current_repository.name_with_display_owner}\" was successfully unarchived."
    redirect_to :back
  end

  def update_member # rubocop:todo GitHub/UseRestfulActions
    if member = User.find_by_login(params[:member_login])
      begin
        action = Role.find_role_name!(role_name: params[:permission], repository: current_repository)
      rescue ArgumentError, ActiveRecord::RecordNotFound
        flash[:error] = "Invalid permission specified."
        redirect_to :back
      else
        if current_repository.update_member(member, action: action, actor: current_user)
          render json: { action: action }
        else
          render_404
        end
      end
    else
      render_404
    end
  end

  def remove_member # rubocop:todo GitHub/UseRestfulActions
    @member = User.find_by_login(params[:member])
    current_repository.remove_member(@member, current_user)

    respond_to do |wants|
      wants.html do
        if request&.xhr?
          head :ok
        else
          name          = (@member == current_user) ? "yourself" : @member.display_login
          flash_message = "Removed #{name} as a collaborator of #{current_repository.name_with_display_owner}"

          if current_repository.adminable_by?(current_user)
            redirect_to :back, flash: { notice: flash_message }
          else
            redirect_to "/", flash: { notice: flash_message }
          end
        end
      end
    end
  end

  def add_team # rubocop:todo GitHub/UseRestfulActions
    team = if params[:team]
      current_repository.organization.teams.find(params[:team])
    elsif params[:team_slug]
      current_repository.organization.teams.find_by_slug(params[:team_slug])
    end

    if current_repository.teams.include?(team)
      return respond_to do |wants|
        wants.html { redirect_to repository_access_management_path(current_repository.owner, current_repository) }
        wants.json { render json: { error: error_message_for(Team::ModifyRepositoryStatus::DUPE) } }
      end
    end

    if current_repository.can_add_to_team?(team, adder: current_user)
      status = team.add_repository(current_repository, :pull)

      if status == Team::ModifyRepositoryStatus::SUCCESS
        respond_to do |wants|
          wants.html { redirect_to repository_access_management_path(current_repository.owner, current_repository) }
          wants.json do
            direct_access_list = ::RepositoryAccessList.new(
              repository: current_repository,
              current_user: current_user,
            )
            repository_roles = ::RepositoryMemberRoles.fetch(
              repository:   current_repository,
              current_user: current_user,
              members:      direct_access_list.user_results,
              teams:        direct_access_list.repository_teams,
            )
            render json: {
              name: team.name,
              html: render_to_string(
                partial: "edit_repositories/admin_screen/access_management/team", locals: {
                  team: team,
                  organization: team.organization,
                  view: create_view_model(
                    EditRepositories::Pages::ManagedAccessPageView,
                    repository: current_repository,
                    current_user:,
                    repository_roles:,
                    direct_access_list:
                  )
                },
                formats: [:html]
              ),
            }
          end
        end
      else
        respond_to do |wants|
          wants.html { redirect_to repository_access_management_path(current_repository.owner, current_repository) }
          wants.json { render json: { error: error_message_for(status) } }
        end
      end
    else
      respond_to do |wants|
        wants.html { redirect_to repository_access_management_path(current_repository.owner, current_repository) }
        wants.json { render json: { error: "Team not found" } }
      end
    end
  end

  def remove_team # rubocop:todo GitHub/UseRestfulActions
    # Note: we don't need to do any permissions-checking here. We already know
    # the user has admin on the repo (every action in this controller is
    # protected by an admin check on the repo, see ensure_admin_access in the
    # AbstractRepositoryController controller for more), and a user with admin
    # on a repo should be able to remove any teams from that repo, regadless of
    # the user's permissions with those teams.

    if check_business_teams?
      @team = Orgs.domain.teams.find_team_in_organization(
        business_id: current_repository.organization.business&.id,
        organization_id: current_repository.organization.id,
        team_id: params[:team].to_i)
    else
      @team = Team.find_by(id: params[:team])
    end

    if @team
      @team.remove_repository(current_repository)
      respond_to do |wants|
        wants.html do
          if request&.xhr?
            head :ok
          else
            redirect_to repository_access_management_path(current_repository.owner, current_repository)
          end
        end
      end
    else
      respond_to do |wants|
        wants.html { redirect_to repository_access_management_path(current_repository.owner, current_repository) }
        wants.json { render json: { error: "Team not found" } }
      end
    end
  end

  def detach # rubocop:todo GitHub/UseRestfulActions
    begin
      if current_repository.cannot_detach_repository_reason
        flash[:error] = "You cannot detach this repository."
      else
        GitHub.dogstats.increment("repo.self_service_detach.count")
        GitHub.logger.info("Self service fork detach",
        {
          "gh.actor.id" => current_user&.id,
          "gh.repo.id" => current_repository.id,
          "gh.repo.network_id" => current_repository.network_id,
          "gh.repo.owner_id" => current_repository.owner_id
        })
        current_repository.detach!
        flash[:notice] = "Detaching this repository."
      end
    rescue Repository::NetworkDependency::DetachFailure => e
      flash[:error] = e.message
    end
    redirect_to edit_repository_path(current_repository)
  end

  def set_visibility # rubocop:todo GitHub/UseRestfulActions
    unless repo_name_verification_valid?(params[:verify])
      flash[:error] = "You must type the name of the repository to confirm."
      return redirect_to edit_repository_path(current_repository)
    end

    if current_repository.fork? && current_repository.matches_root_visibility?
      return redirect_to edit_repository_path(current_repository)
    end

    # do not allow permission changes when a host is offline since we need to
    # sync the public permission bit.
    if !current_repository.online?
      flash[:error] = "Sorry, repository visibility cannot be changed at this time."
      return redirect_to edit_repository_path(current_repository)
    end

    if T.must(current_user).emu_creating_public_repo?(params[:visibility])
      flash[:error] = "Enterprise managed resources can't have #{Repository::PUBLIC_VISIBILITY} visibility"
      return redirect_to edit_repository_path(current_repository)
    end

    begin
      current_repository.set_visibility(actor: current_user, visibility: params[:visibility])
    rescue Repositories::Error::VisibilityLocked
      flash[:error] = "Sorry, repository visibility cannot be changed at this time. A previous visibility change is still in progress."
      return redirect_to edit_repository_path(current_repository)
    end

    if current_repository.errors[:visibility_restricted].any?
      flash[:trade_controls_organization_owned_repo_disabled] = true
      return redirect_to edit_repository_path(current_repository)
    end

    if current_repository.errors[:visibility].any?
      flash[:error] = current_repository.errors.full_messages.to_sentence
      return redirect_to edit_repository_path(current_repository)
    end

    respond_to do |wants|
      wants.html do
        if request&.xhr?
          head :ok
        elsif params[:return_to].present?
          safe_redirect_to params[:return_to]
        else
          redirect_to edit_repository_path(current_repository)
        end
      end
    end
  end

  def rename # rubocop:todo GitHub/UseRestfulActions
    new_name_is_blank = params[:new_name].blank?
    normalized_name = EntityName.normalize(params[:new_name].to_s) unless new_name_is_blank
    if new_name_is_blank || normalized_name == current_repository.name
      flash[:error] = "Repository name was not changed"
      return redirect_to edit_repository_path(current_repository)
    end

    if current_repository.rename(normalized_name, actor: current_user)
      redirect_to repository_path(current_repository)
    else
      if current_repository.errors.any?
        flash[:error] = current_repository.errors.full_messages.to_sentence
      else
        flash[:error] = "Couldn’t rename repository to #{normalized_name}"
      end

      redirect_to edit_repository_path(current_repository)
    end
  end

  def transfer_team_suggestions # rubocop:todo GitHub/UseRestfulActions
    org = User.find_by(login: params[:new_owner])
    return render_404 unless org&.organization?

    paginated_teams = paginated_teams_search(org)

    render(json: { data: react_team_selections_payload(paginated_teams) }, status: :ok)
  end

  def transfer # rubocop:todo GitHub/UseRestfulActions
    new_owner = User.find_by(login: params[:new_owner])

    transfer_request = RepositoryTransfer.new(
      repository: current_repository,
      requester: current_user,
      target: new_owner,
      requested_target: params[:new_owner],
      new_name: params[:new_name],
      custom_properties: custom_properties_from_params,
    )

    if new_owner&.organization?
      definitions = Repositories.domain.custom_properties.get_definitions(T.cast(new_owner, Organization))
      required_properties_present = definitions.any? { |definition| definition.required }
    end

    tags = ["form:transfer"]
    tags << "rename:#{params["new_name"].present? && params["new_name"] != params["repository"] ? "true" : "false"}"
    tags << "custom_properties:#{custom_properties_from_params.present?}"
    tags << "required_properties_present:#{required_properties_present}"
    tags << "error:#{transfer_request.invalid? ? "true" : "false"}"
    GitHub.dogstats.increment("repos_form_submit", tags: tags)

    if transfer_request.invalid?
      return render(json: { data: { error: html_escape(transfer_request.errors.full_messages.to_sentence) }, code: 422 }, status: :unprocessable_entity)
    end

    may_assign_teams = may_assign_teams_after_transfer?(new_owner)
    if !may_assign_teams && params[:team_ids]
      return head :bad_request
    end

    if may_assign_teams && params[:teams_selection].blank?
      paginated_teams = paginated_teams_search(new_owner)
      return render(json: { data: react_team_selections_payload(paginated_teams) }, status: :ok)
    end

    if RepositoryTransfer.requires_transfer_request?(target: new_owner, requester: current_user, repository_visibility: current_repository.visibility)
      if params[:new_name] != current_repository.name
        GitHub.dogstats.increment("repository.transfer.actual_or_potential_name_conflict", tags: ["location:controller"])
        render(json: { data: { error: "This repository cannot be renamed on transfer. Please transfer without a rename." }, code: 422 }, status: :unprocessable_entity)
      else
        RepositoryTransfer.start current_repository, new_owner, current_user
        flash[:notice] = "Repository transfer to #{params[:new_owner]} requested"
        render(json: { data: { redirect: edit_repository_path(current_repository) } }, status: :ok)
      end
    else
      team_ids = params[:team_ids] || ""
      team_ids = team_ids.split(",") unless team_ids.is_a?(Array)
      team_ids = team_ids.map(&:to_i).uniq

      new_owner = T.must(new_owner)
      teams_scope = if new_owner.organization?
        T.cast(new_owner, Organization).visible_teams_for(current_user)
      else
        new_owner.teams
      end

      target_teams = teams_scope.where(id: team_ids)
      RepositoryTransfer.transfer_immediately(
        current_repository, new_owner,
        current_user, target_teams,
        transfer_request.new_name,
        custom_properties: custom_properties_from_params
      )
      flash[:notice] = "Moving repository to #{new_owner.display_login}/#{transfer_request.new_name}. This may take a few minutes."

      respond_to do |format|
        format.html do
          redirect_to user_or_org_repos_path
        end
        format.json do
          render(json: { data: { redirect: user_or_org_repos_path } }, status: :ok)
        end
      end
    end
  rescue Exception => e # rubocop:todo Lint/RescueException
    Failbot.report e
    render(json: { data: { error: html_escape(transfer_request&.errors&.full_messages&.to_sentence) }, code: 422 }, status: :unprocessable_entity)
  end

  def abort_transfer # rubocop:todo GitHub/UseRestfulActions
    if current_repository.pending_transfer?
      current_repository.pending_transfer.destroy
    end

    redirect_to edit_repository_path(current_repository)
  end

  def tabs # rubocop:todo GitHub/UseRestfulActions
    render "edit_repositories/pages/tabs"
  end

  def add_tab # rubocop:todo GitHub/UseRestfulActions
    tab = Tab.new(anchor: params[:anchor], url: params[:url])

    if tab.valid?
      current_repository.tabs << tab
    else
      flash[:error] = if tab.errors.any?
        tab.errors.full_messages.to_sentence
      else
        "Tab is invalid."
      end
    end

    respond_to do |wants|
      wants.html do
        if request&.xhr?
          head :ok
        else
          redirect_to edit_repository_path(current_repository) + "/tabs"
        end
      end
    end
  end

  def remove_tab # rubocop:todo GitHub/UseRestfulActions
    tab = current_repository.tabs.find(params[:tab])
    tab.destroy if tab

    respond_to do |wants|
      wants.html do
        if request&.xhr?
          head :ok
        else
          redirect_to T.unsafe(self).repository_tabs_path
        end
      end
    end
  end

  def change_anonymous_git_access # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.anonymous_git_access_enabled?

    unless repo_name_verification_valid?(params[:verify])
      flash[:error] = "You must type the name of the repository to confirm."
      return redirect_to edit_repository_path(current_repository)
    end

    val = params[:value]&.to_s
    if current_repository.fork?
      flash[:error] = Repository::AnonymousGitAccess::FORK_ERROR
    elsif current_repository.anonymous_git_access_locked?(current_user)
      flash[:error] = "#{Repository::AnonymousGitAccess::LOCKED_ERROR}.  Please contact a site administrator."
    elsif val == "true"
      current_repository.enable_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access is now enabled."
    elsif val == "false"
      current_repository.disable_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access is now disabled."
    else
      flash[:error] = "Failed to change anonymous Git read access."
    end

    redirect_to edit_repository_path(current_repository)
  end

  def unpublish_page # rubocop:todo GitHub/UseRestfulActions
    current_repository.unpublish_page
    flash[:notice] = "Your repository page has been unpublished."
    redirect_to edit_repository_path(current_repository)
  end

  def reported_content # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.can_access_tiered_reporting?(current_user)

    resolved_filter = params[:resolved_filter] == "RESOLVED" ? "RESOLVED" : "UNRESOLVED"

    latest_reports = AbuseReport.
      where(repository: current_repository, resolved: resolved_filter == "RESOLVED", show_to_maintainer: true).
      includes(:reported_content).
      not_spammy.
      most_recent_for_each_reported_content(current_repository.id).
      reject(&:content_spammy?). # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      paginate(per_page: REPORTED_CONTENT_PER_PAGE, page: current_page)

    reported_contents = latest_reports.map(&:reported_content).compact

    report_counts = AbuseReport.where(repository: current_repository, show_to_maintainer: true, reported_content: reported_contents).group(:reported_content_type, :reported_content_id).count

    comments_with_info = []

    if reported_contents.any?
      promises = reported_contents.each_with_index.map do |content, index|
        comment_with_info(content, report_counts, latest_reports[index])
      end
      comments_with_info = Promise.all(promises).sync
    end

    render "edit_repositories/pages/reported_content",
      locals: { current_repository: current_repository,
                resolved_filter: resolved_filter,
                report_content_prior_contributors_enabled: current_repository.tiered_reporting_explicitly_enabled?,
                report_content_all_users_enabled: current_repository.tiered_reporting_all_users_explicitly_enabled?,
                comments_with_info: comments_with_info,
                paginated_reports: latest_reports,
              }
  end

  def abuse_reporters # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.can_access_tiered_reporting?(current_user) && request&.xhr?

    reports = AbuseReport.where(reported_content_type: params[:type], reported_content_id: params[:id], show_to_maintainer: true).limit(REPORTED_CONTENT_PER_PAGE)

    render partial: "community/repo_abuse_reporters",
      locals: { abuse_reports: reports },
      layout: false
  end

  # Returns a promise that resolves to a fully completed hash
  def comment_with_info(comment, report_counts, latest_report) # rubocop:todo GitHub/UseRestfulActions
    Platform::Loaders::TopReportedAbuseReason.load(comment).then do |top_abuse_reason|
      {
        comment: comment,
        top_reason: top_abuse_reason,
        last_reported: latest_report.created_at,
        report_count: report_counts[[comment.class.to_s, comment.id]],
      }
    end
  end

  def toggle_tiered_reporting # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository.can_enable_tiered_reporting?(current_user)

    case params[:tiered_reporting_settings]
    when EditRepositories::TieredReportingForm::ALLOW_ALL_USERS
      current_repository.disable_tiered_reporting(actor: current_user)
      current_repository.enable_tiered_reporting_all_users(actor: current_user)
      flash[:notice] = "Content reporting enabled for all users on this repository"
    when EditRepositories::TieredReportingForm::PRIOR_CONTRIBUTORS # also includes collaborators
      current_repository.enable_tiered_reporting(actor: current_user)
      current_repository.disable_tiered_reporting_all_users(actor: current_user)
      flash[:notice] = "Content reporting enabled for prior contributors and collaborators on this repository"
    when EditRepositories::TieredReportingForm::DISABLE
      current_repository.disable_tiered_reporting(actor: current_user)
      current_repository.disable_tiered_reporting_all_users(actor: current_user)
      flash[:notice] = "Content reporting is disabled for this repository"
    end

    redirect_to reported_content_path
  end

  private

  def branch_name_for_display
    params[:name].dup.force_encoding("UTF-8").scrub!
  end
  helper_method :branch_name_for_display

  def handle_request_response(redirect_to = :back)
    if request&.xhr?
      # TODO: Should handle with live updates.
      respond_to do |format|
        format.html do
          render Repositories::UnderlineNavComponent.new(
            repository: current_repository,
            selected_link: :repo_settings,
            display_variant: :padded,
            user_can_write_wiki: current_user_can_write_wiki?
          ), layout: false
        end
      end
    elsif current_repository.errors.any?
      flash[:error] = "Error saving your changes: #{current_repository.errors.full_messages.to_sentence}"
      redirect_to redirect_to
    else
      flash[:notice] = "Repository settings saved." unless flash[:error].present? || flash[:notice].present?
      redirect_to redirect_to
    end
  end

  # We allow access to the admin page in some cases where we don't allow access
  # to the code. To allow for this, we must override the
  # AbstractRepositoryController#ask_the_gatekeeper method for these cases
  #
  # See AbstractRepositoryController#ask_the_gatekeeper for more details
  def ask_the_gatekeeper
    repo = current_repository
    state = params[:fakestate] if real_user_site_admin?

    super if repo&.private? && (repo&.trade_restricted_by_owner? || current_user&.has_any_trade_restrictions?)

    # Allow disabled accounts to edit their repos
    unless (repository_specified? && repo && repo.disabled?(viewer: current_user)) || state == "disabled"
      super
    end
  end

  private def has_base_repo_permissions_to_view_settings
    permission = current_repository.async_action_or_role_level_for(current_user, include_custom_roles: false).sync
    [:maintain, :admin].include?(permission) || moderator_can_view_settings?
  end

  private def privacy_check_with_custom_role_support
    if current_repository.owner.custom_roles_supported?
      current_repository.async_can_view_repository_settings?(current_user).sync
    else
      has_base_repo_permissions_to_view_settings
    end
  end

  private def privacy_check_with_fgp_org_base_role
    current_repository.async_can_view_repository_settings?(current_user).sync ||
    has_base_repo_permissions_to_view_settings
  end

  # Override RepositoryControllerMethods#privacy_check.
  def privacy_check
    has_permissions = if FeatureFlag.vexi.enabled?(:remove_custom_role_requirement_repo_settings, current_repository&.owner, default: false)
      privacy_check_with_fgp_org_base_role
    else
      privacy_check_with_custom_role_support
    end

    return if has_permissions
    return render "admin/locked_repo" if logged_in? && current_user&.site_admin?
    render_404
  end

  # Internal: Get a user-readable error message describing the specified
  # Team::ModifyRepositoryStatus.
  #
  # modify_repository_status - Team::ModifyRepositoryStatus to get a message for.
  #
  # Returns a string or nil.
  def error_message_for(modify_repository_status)
    case modify_repository_status
    when Team::ModifyRepositoryStatus::DUPE
      "This team already has access to this repository."
    when Team::ModifyRepositoryStatus::NOT_OWNED
      "This team belongs to a different organization than this repository."
    when Team::ModifyRepositoryStatus::OWNERS
      "The Owners team already has access to all of this organization’s repositories."
    end
  end

  def ensure_user_can_manage_deploy_keys
    render_404 unless current_repository.async_can_manage_deploy_keys?(current_user).sync
  end

  def may_assign_teams_after_transfer?(new_owner)
    return false unless new_owner&.organization?
    return false unless new_owner.adminable_by?(current_user)
    return false if new_owner.visible_teams_for(current_user).empty?

    new_owner.can_create_repository?(current_user, visibility: current_repository.visibility)
  end

  def repo_name_verification_valid?(repo_name)
    current_repository.name_with_display_owner.casecmp?(repo_name)
  end

  def custom_tabs_only
    render_404 unless GitHub.custom_tabs_enabled?
  end

  def metadata_permissions_required
    render_404 unless current_repository.can_edit_repo_metadata?(current_user)
  end

  def manage_topics_permissions_required
    render_404 unless current_repository.can_manage_topics?(current_user)
  end

  def wiki_settings_permissions_required
    render_404 unless current_repository.can_toggle_wiki?(current_user)
  end

  def projects_settings_permissions_required
    render_404 unless current_repository.async_can_toggle_projects?(current_user).sync
  end

  def toggle_merge_types_permissions_required
    render_404 unless current_repository.async_can_toggle_merge_settings?(current_user).sync
  end

  # Fetch all the members of the current repo.
  # If params[:member_ids] contains any ids, only return the ids which are collaborators of the repo
  #
  # Returns an ActiveRecord::Relation
  def selected_members_for_user_repo
    if params[:member_ids].present?
      current_repository.all_members.select { |member| params[:member_ids].include?(member.id) }
    else
      current_repository.all_members
    end
  end

  # Private: is the member an owner of the organization that owns the current repository?
  #
  # - member: a User
  #
  # Returns a Boolean
  def org_owner?(member)
    return false unless current_repository.in_organization?

    # an org-owner is a member who can admin the organization
    current_repository.organization.adminable_by?(member)
  end

  def enqueue_sync_package_access_job
    Packages::SyncPackagePermsOnRepoChangeJob.perform_later(repository: current_repository)
  end

  def paginated_teams_search(org)
    paginated_teams(org.team_search_for_user(TeamSearchQuery.new(params[:query]), current_user))
  end

  def paginated_teams(teams)
    total_entries = teams.size
    teams = teams.paginate(page: current_page, per_page: TEAM_SUGGESTIONS_PAGE_SIZE)

    WillPaginate::Collection.create(current_page, TEAM_SUGGESTIONS_PAGE_SIZE) do |pager|
      pager.replace(teams)
      pager.total_entries = total_entries
    end
  end

  def user_or_org_repos_path
    if current_repository.in_organization? && !current_repository.fork?
      org_repositories_path(current_repository.organization)
    else
      user_path(current_user, params: { tab: :repositories })
    end
  end

  def react_team_selections_payload(paginated_teams)
    teams = paginated_teams.map do |team|
      {
        id: team.id,
        name: team.name,
        path: team_path(team),
        description: team.description,
        members_scope_count: pluralize(team.members_scope_count, "member"),
        repositories_scope_count: pluralize(team.repositories_scope_count, "repository")
      }
    end

    Repos::ReactPayload.camelize_keys({ # rubocop:disable GitHub/AvoidCamelizeKeys
      teams: teams,
      page_count: paginated_teams.total_pages
    })
  end

  # Private: Indicates if the current user is able to view the repo settings page with limited options.
  #          WARNING: This does not check if the user has the needed FGPs. That is handled in `privacy_check`.
  def fgp_options_page_viewable?
    return false unless owner = current_repository.owner
    return false unless owner.organization?
    return true if owner.plan_supports?(:fine_grained_permissions)
    moderator_can_view_settings?
  end

  # Private: Indicates if the current user is a moderator and can view repo settings.
  #          This is used for orgs without fine grained permissions – FGP orgs have
  #          permission checks that do this in authzd.
  def moderator_can_view_settings?
    return false unless owner = current_repository.owner
    return false unless owner.organization?
    current_repository.public? && owner.moderator?(current_user)
  end

  def plan_supports_enterprise_rulesets
    render_404 unless current_repository.plan_supports?(:enterprise_rulesets) || current_repository.in_organization?
  end

  def custom_properties_from_params
    return nil unless params.key?(:custom_properties)

    params.fetch(:custom_properties).permit!.to_h
  end

  def check_business_teams?
    current_repository.organization&.business&.enterprise_teams_org_roles_supported?
  end
end
