# typed: false
# frozen_string_literal: true

# FilesController is all about browsing files on GitHub. This controller is
# used for both private and public content, so there is a mixture of
# authenticated requests and non-authenticated requests.
class FilesController < GitContentController
  include BranchesHelper
  include Repos::TreePayloadHelper
  include Repos::CodeViewHelper
  include AvatarHelper
  include ActionView::Helpers::DateHelper
  include InteractionBanHelper
  include DesktopHelper
  include StacksHelper
  include RepositoriesHelper
  include ShellHelper
  include RegistryTwo::PackagesMigrationHelper

  self.react_bundle_name = "react-code-view"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::Notify,
    ApplicationRecord::Iam,
    ApplicationRecord::ActionsEnvironments,
    ApplicationRecord::Pages,
    only: [:disambiguate]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:commit_info]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:branch_infobar]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:branch_count, :tag_count, :branch_and_tag_count]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:latest_commit, :contributors]

  depends_on_clusters ApplicationRecord::Spokes,
    optional: true, only: [:disambiguate, :commit_info, :branch_infobar, :latest_commit, :contributors]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true, only: [:disambiguate]

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    optional: true, only: [:disambiguate, :latest_commit, :branch_infobar, :contributors, :commit_info]

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    optional: true, only: [:disambiguate, :latest_commit, :contributors, :commit_info]

  depends_on_clusters ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesActionsChecks,
    optional: true, only: [:disambiguate, :latest_commit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:commit_info, :contributors, :latest_commit],
    optional: true

  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(disambiguate latest_commit commit_info contributors).freeze

  # As of 2019-04-16, disambiguate is averaging around 580 rq/sec, or around 3%
  # of total requests
  set_statsd_sample_rate 0.01, only: :disambiguate

  include TreeHelper
  include ControllerMethods::Codespaces
  include Codespaces
  include CodeviewCustomErrorDependency

  layout :current_layout
  javascript_bundle :codespaces
  javascript_bundle :repositories
  javascript_bundle :"code-menu"
  javascript_bundle :"copilot-coding-agent-status"
  stylesheet_bundle :code

  before_action :raw_redirect, only: [:disambiguate]
  before_action :redirect_for_missing_branch, only: [:disambiguate]
  before_action :ensure_commit_sha, only: [:disambiguate]

  def branch_count # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.distribution_time("files.branch_and_tag_count", tags: ["count_type:branch"]) do
      respond_to do |format|
        format.html do
          render partial: "files/branch_count", locals: { branch_count: current_repository.heads.size }
        end
      end
    end
  end

  def tag_count # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.distribution_time("files.branch_and_tag_count", tags: ["count_type:tag"]) do
      respond_to do |format|
        format.html do
          render partial: "files/tag_count", locals: { tag_count: current_repository.tags.size }
        end
      end
    end
  end

  def branch_and_tag_count # rubocop:todo GitHub/UseRestfulActions
    loader = Git::Ref::Loader.new(current_repository, "default")
    branch_and_tag_count_hash = loader.branches_and_tags_count
    respond_to do |format|
      format.html do
        render partial: "files/branch_and_tag_count", locals: { repository: current_repository, branch_count: branch_and_tag_count_hash[:branches], tag_count: branch_and_tag_count_hash[:tags] }
      end
      format.json do
        render json: branch_and_tag_count_hash
      end
    end
  end

  param_encoding :disambiguate, :name, "ASCII-8BIT"

  # This is the catchall for all repository file listing pages
  #
  # The url structure for these pages makes it impossible to check
  # where the ref-name stops and the path starts. We have to look
  # at the refs on the repository. See GitHub::RefShaPathExtractor
  # for how we do this.
  #
  # This is due to the possibility of there being foward-slashes in
  # ref names. Given the url /user/repo/tree/foo/bar/bang
  # That could be:
  #
  # ref: foo, path: bar/bang
  # ref: foo/bar, path: bang
  # ref: foo/bar/bang, path: [root]
  #
  # If the path ends up empty, we are at the root of the repo and
  # should show the overview page. Otherwise we are in a subdirectory.
  #
  # params[:path] and params[:name] are set in:
  # AbstractRepositoryController#set_path_and_name
  def disambiguate # rubocop:todo GitHub/UseRestfulActions
    render_codeview_404 and return if @render_codeview_404
    render_codeview_500 and return if @render_database_error && should_subdirectory?

    current_directory&.simplify_paths

    if should_subdirectory?
      subdirectory
    else
      overview
    end
  rescue GitRPC::InvalidObject => boom
    if boom.message =~ /expected tree, got blob/
      blob_redirect boom
    else
      raise
    end
  rescue GitRPC::NoSuchPath
    if custom_codeview_404?(true)
      render_codeview_404 and return
    else
      flash.now[:warn] = "The '#{current_repository.name_with_display_owner}' repository doesn't contain the '#{path_string_for_display}' path in '#{tree_name_for_display}'." if path_string.present?
      raise
    end
  # We shouldn't get these, but salvage if we do
  rescue Rugged::OdbError, Rugged::ReferenceError, GitRPC::Error
    if !should_subdirectory?
      @render_database_error = true
      overview
    else
      raise
    end
  end

  def react_payload(include_readme = true, is_overview = false) # rubocop:todo GitHub/UseRestfulActions
    # Adding for the overview doesn't help, because the flags get set in the app payload as part of
    # render_react_app. The flags are added to the app payload manually for overview.
    if !is_overview
      add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)
    end
    add_csrf_token(create_branch_path, :post)

    # When the user is browsing repo at a particular commit, she cannot update branch or discard changes, so tokens are not needed.
    if current_branch_or_tag_name_for_urls
      # Update branch
      add_csrf_token(fetch_and_merge_path(current_repository.owner, current_repository, current_branch_or_tag_name_for_urls.force_encoding("utf-8").scrub), :post)
      # Discard changes
      add_csrf_token(fetch_and_merge_path(current_repository.owner, current_repository, current_branch_or_tag_name_for_urls.force_encoding("utf-8").scrub, discard_changes: true), :post)
    end

    if @render_database_error
      payload = helpers.repo_error_payload({ httpStatus: 500, type: "httpError" })
    else
      payload = page_tree_payload(current_directory, include_readme, is_overview)
    end

    # No file tree on the overview page

    if is_overview
      tree_expanded = false
    else
      tree_expanded = logged_in? ? current_user.settings.get(:tree_view_expanded) : true
    end
    payload[:treeExpanded] = tree_expanded
    # Symbols pane can't be opened on overview or subdirectory pages
    payload[:symbolsExpanded] = false
    payload
  end

  def subdirectory # rubocop:todo GitHub/UseRestfulActions
    # Routes format must be set to false to avoid inferring request format from the file extension.
    # At the same time default file format must be set to `:html` to ensure that rails pages work as expected.
    # According to the docs default format cannot be overridden, therefore we need to set it explicitly based on the
    # Accept header.
    request.format = :json if json_request?

    # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
    # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
    @rendering_react_view = true
    render_react_app(
      app_payload_generator: -> { app_payload },
      payload: react_payload,
      page_data: {
        selected_link: :repo_source,
        send_vitals: true,
        richweb: {
          title: page_title.to_s,
          url: repository_url(current_repository, current_ref, path_string),
          description: force_escape_with_transcoding_guess(repo_meta_description),
          image: repository_open_graph_image_url(current_repository),
          card: repository_twitter_image_card(current_repository)
        }
      },
      title: page_title,
      turbo: {
        id: "repo-content-turbo-frame",
        target: "_top",
        action: "advance",
        class: ""
      },
      disable_ssr: !GitHub.flipper[:react_blob_ssr].enabled?(current_user),
    )
  end

  def overview # rubocop:todo GitHub/UseRestfulActions
    if ref.blank? || ref == current_repository.default_branch
      # Override the default behavior of `analytics_location_meta_tag` where the
      # reported URL would end with "/files/disambiguate" which would make it
      # impossible to distinguish whether someone was visiting the project home
      # page vs. drilling down into subdirectories.
      override_analytics_location "/<user-name>/<repo-name>"
    end
    payload = react_payload(false, true)
    payload[:isOverview] = true
    application_payload = app_payload
    add_client_feature_flag(
      [:copilot_workspace],
      entity: current_repository.owner
    ) do |_feature_name, owner|
      feature_enabled_globally_or_for_current_user_or_entity?(:copilot_workspace, owner) || current_user&.copilot_workspace_can_grant_auto_access?
    end
    application_payload[:enabled_features] = add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)

    user_checks_for_publish_banners = (
      logged_in? &&
      !GitHub.enterprise? &&
      current_user_can_push?
    )

    interaction_ability = RepositoryInteractionAbility.new(current_repository)
    active_limit = with_database_error_fallback(fallback: :no_limit) do
      interaction_ability.overall_active_limit
    end

    if GitHub.interaction_limits_enabled? && !current_repository.private? && current_repository.can_set_interaction_limits?(current_user) && active_limit != :no_limit && interaction_ability.active_limit_origin != :repository
      limit_owner = current_repository.owner

      limit_name = case active_limit
      when :sockpuppet_disallowed
        "existing users"
      when :contributors_only
        "prior contributors"
      when :collaborators_only
        "collaborators"
      end

      limit_owner_word = limit_owner.organization? ? limit_owner.display_login : "your account"

      limit_title = "Public repositories in #{limit_owner_word} are currently limited to #{limit_name}"

      if limit_owner.can_set_interaction_limits?(current_user)
        if limit_owner.organization?
          admin_link = org_interaction_limits_path(limit_owner)
          admin_text = "organization settings"
          disable_path = update_org_interaction_limits_path(limit_owner)
        else
          admin_link = settings_interaction_limits_path
          admin_text = "interaction limit settings"
          disable_path = settings_interaction_limits_path
        end
      end

      interaction_limit_banner = {
        adminLink: admin_link,
        adminText: admin_text,
        currentExpiry: distance_of_time_in_words_to_now(interaction_ability.overall_active_limit_expiry),
        disablePath: disable_path,
        limitTitle: limit_title,
        inOrganization: limit_owner.organization?,
        usersHaveAccess: active_limit == :sockpuppet_disallowed,
        contributorsHaveAccess: active_limit != :collaborators_only,
      }
    end

    if logged_in?
      invitation = current_user.received_repository_invitations.find_by_repository_id(current_repository.id)
    end

    if !@render_database_error
      overview_files, overview_files_processing_time = overview_files_timeboxed(true, params[:tab])
    end

    if show_branch_rename_instructions_popover?(tree_type: tree_type)
      rename = latest_default_branch_rename
      if shell_safe_names_include_placeholders?([[":branch", rename.old_name_for_display], [":branch", rename.new_name_for_display]])
        shell_escaping_docs_url = ShellHelper::SHELL_ESCAPING_DOCS_URL
      end

      rename_info = {
        oldName: rename.old_name_for_display,
        shellOldName: shell_safe_name(":branch", rename.old_name_for_display),
        newName: rename.new_name_for_display,
        shellNewName: shell_safe_name(":branch", rename.new_name_for_display),
        shellEscapingDocsURL: shell_escaping_docs_url
      }
    elsif show_parent_branch_rename_instructions_popover?(tree_type: tree_type)
      parent_rename_info = {
        nameWithOwner: current_repository.parent&.name_with_display_owner,
        branchName: current_repository.parent&.default_branch,
      }
    end

    migration_enabled = current_repository.feature_enabled?(:migrate_to_immutable_actions) || current_repository.owner.feature_enabled?(:migrate_to_immutable_actions)
    release_tags = []
    migration_status = nil
    if migration_enabled
      release_tags = current_repository.releases.limit(1000).pluck(:tag_name).uniq
      migration_status = get_migration_status_value(current_repository)
    end

    migration_banner_info = {
      releaseTags: release_tags,
      showImmutableActionsMigrationBanner: show_immutable_actions_migration_banner?(migration_enabled, release_tags, migration_status),
      initialMigrationStatus: migration_status
    }

    overview_info = {
      banners: {
        shouldRecommendReadme: !@render_database_error && should_recommend_readme? && current_repository.heads.exist?(tree_name),
        isPersonalRepo: current_repository.private? && current_repository.members.size < 1,
        showUseActionBanner: !GitHub.enterprise? && current_repository.listed_action.present?,
        actionSlug: current_repository.listed_action&.slug,
        actionId: current_repository.listed_action&.id,
        showProtectBranchBanner: show_protect_this_branch_banner?(tree_name) && !current_repository.advisory_workspace?,
        publishBannersInfo: {
          dismissActionNoticePath: dismiss_notice_path(UserNotice::PUBLISH_ACTION_FROM_REPO_NOTICE),
          releasePath: new_release_path_helper(query_params: { marketplace: true }),
          showPublishActionBanner: (
            user_checks_for_publish_banners &&
            !current_user.dismissed_notice?(UserNotice::PUBLISH_ACTION_FROM_REPO_NOTICE) &&
            current_repository.listable_action? &&
            current_repository.listed_action.nil?
          ),
        },
        interactionLimitBanner: interaction_limit_banner,
        showInvitationBanner: logged_in? && current_repository.public? && invitation.present?,
        inviterName: invitation&.inviter&.display_login,
        # TODO check that migration hasn't started/finished
        actionsMigrationBannerInfo: migration_banner_info
      },
      codeButton: {
        contactPath: contact_path,
        isEnterprise: GitHub.enterprise?,
        local: {
          protocolInfo: get_local_protocol_info,
          platformInfo: {
            cloneUrl: app_clone_url(current_repository, nil, current_branch_or_tag_name),
            showVisualStudioCloneButton: visual_studio_clone_button?,
            visualStudioCloneUrl: visual_studio_clone_url(current_repository),
            showXcodeCloneButton: xcode_clone_button?,
            xcodeCloneUrl: xcode_clone_url(current_repository),
            zipballUrl: zipball_path(current_repository.owner, current_repository, name_for_codeload.try { |s| s.dup.force_encoding(::Encoding::UTF_8).scrub! })
          }
        }
      },
      popovers: {
        rename: rename_info,
        renamedParentRepo: parent_rename_info,
      },
      commitCount: current_commit ? limitless_commit_count(current_commit.oid) : 0,
      overviewFiles: overview_files,
      overviewFilesProcessingTime: 0, # remove in a couple of weeks
    }

    if logged_in?
      overview_info[:createFromTemplatePath] = clone_template_repository_url(current_user, current_repository)
    end

    if logged_in?
      repository_policy = with_database_error_fallback(fallback: nil) do
        Codespaces::RepositoryPolicy.async_with_prefill(current_user, current_repository).sync
      end

      if repository_policy.present?
        repository_policy_info = {
          allowed: repository_policy.allowed?,
          canBill: repository_policy.can_bill?,
          changesWouldBeSafe: repository_policy.changes_would_be_safe?,
          disabledByBusiness: repository_policy.disabled_by_business?,
          disabledByOrganization: repository_policy.disabled_by_organization?,
          hasIpAllowLists: repository_policy.has_ip_allowlists?
        }
        overview_info[:codeButton][:repoPolicyInfo] = repository_policy_info
        overview_info[:codeButton][:currentUserIsEnterpriseManaged] = current_user.is_enterprise_managed?
        overview_info[:codeButton][:enterpriseManagedBusinessName] = current_user.enterprise_managed_business&.name

        codespaces_menu_visibility = Codespaces::MenuVisibility.new(
          user: current_user,
          repository_policy: repository_policy,
          pull_request: nil,
        )
        overview_info[:codeButton][:codespacesEnabled] = current_user.codespaces_feature_enabled?
        overview_info[:codeButton][:hasAccessToCodespaces] = codespaces_menu_visibility.has_access_to_codespaces?
      end
    else
      overview_info[:codeButton][:newCodespacePath] = new_codespace_path(repo: current_repository.id, hide_repo_select: true, ref: ref)
    end

    payload[:overview] = overview_info

    respond_to do |format|
      format.html do
        view = create_view_model(
          Files::OverviewView,
          user: current_user,
          repository: current_repository,
          commit: current_commit,
          page_title: page_title,
          source_url: request.url,
          location: controller_name + "#" + action_name,
          cap_view_filter: cap_view_filter
        )
        render "files/overview", locals: {
          commit: current_commit,
          focus_description: params[:focus_description],
          view: view,
          cap_view_filter: cap_view_filter,
          payload: payload,
          app_payload: application_payload,
          codespaces_menu_visibility: codespaces_menu_visibility,
          codespaces_name_param: params[:name],
          current_ref: current_ref,
        }
      end
    end
  end

  def commit_info # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless commit_sha

    current_directory.simplify_paths
    current_directory.tree_history.calculate_all_entries

    prefill_directory_commit_short_messages(current_directory)

    respond_to do |format|
      format.json do
        entries = commit_info_payload(current_directory)

        if entries.nil?
          return render status: :unprocessable_entity, json: { error: "Cannot retrieve commit info for tree" }
        end

        # Top-level keys are the names of the folder entries, so we cannot camelize them.
        render json: entries
      end
    end
  end

  def branch_infobar # rubocop:todo GitHub/UseRestfulActions
    begin
      payload = branch_infobar_payload
    rescue GitRPC::Timeout => boom
      Failbot.report(boom)
      return render status: :unprocessable_entity, json: { error: "Cannot retrieve comparison data" }
    end
    respond_to do |format|
      format.json { render json: payload }
    end
  end

  def latest_commit # rubocop:todo GitHub/UseRestfulActions
    begin
      # there is a known issue where paths outside the 1000 item directory limit will 404 finding the commit this way
      commit = current_repository.async_last_touched(tree_name, path_string).sync

      # if we hit the 1000 item limit, fall back to by contributors
      # this can be remove if/when the 1000 item limit issue is resolved
      if commit.nil? && !current_commit.nil?
        raw_contributors = current_repository.rpc.read_blob_contributors(
          current_commit.oid,
          path_string,
          co_authors: true,
        )
        contributors = raw_contributors["data"]
        last_contribution = contributors.first
        commit = last_contribution && current_repository.commits.find(last_contribution["commit"])
      end

      return render_404 unless commit

      latest_commit = latest_commit_info(commit, qualified_tree_name)

    rescue ActiveRecord::ActiveRecordError, GitRPC::Timeout => boom
      Failbot.report(boom)
      return render json: {
          error: "Cannot retrieve latest commit",
        }, status: :unprocessable_entity
    end

    respond_to do |format|
      format.json do
        render json: latest_commit
      end
    end
  end

  def contributors # rubocop:todo GitHub/UseRestfulActions
    contributor_payload = {
      totalCount: 0,
      users: [],
    }

    if current_commit
      raw_contributors = current_repository.rpc.read_blob_contributors(
        current_commit.oid,
        path_string,
        co_authors: true,
      )

      users = contributor_users(raw_contributors["data"], current_repository)

      contributor_payload = {
        totalCount: users.size,
        users: users,
      }
    end

    respond_to do |format|
      format.json { render json: contributor_payload }
    end
  end

  def recently_touched_branches # rubocop:todo GitHub/UseRestfulActions
    network_repo = current_repository.find_fork_in_network_for_user(current_user)

    if current_user_can_push? || network_repo != current_repository
      branches = GitHub.dogstats.time("recently_touched_branches") do
        get_recent_branches(get_user_fork)
      end

      pr_templates_enabled = GitHub.flipper[:pull_request_templates].enabled?(current_user) || GitHub.flipper[:pull_request_templates].enabled?(current_repository)

      recent_branches_info = branches.map do |branch|

        branch_in_repo = branch[:repo] == current_repository

        comparison_branch = branch_in_repo ? branch[:name] : "#{branch[:repo].owner.display_login}:#{branch[:name]}"
        comparison_range = branch_in_repo ? branch[:name] : "#{current_repository.default_branch}...#{comparison_branch}"

        {
          branchName: branch[:name],
          comparePath: compare_path(current_repository, comparison_range, expand: !pr_templates_enabled),
          date: branch[:date],
          repoName: branch[:repo].name,
          repoOwner: branch[:repo].owner.display_login,
          branchInRpo: branch_in_repo
        }
      end

      data_channel = get_recently_touched_branches_live_update_channel
    end

    respond_to do |format|
      format.json { render json: { channel: data_channel, branches: recent_branches_info } }
    end
  end

  def overview_files # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      overview_files, _overview_files_processing_time = overview_files_timeboxed

      # remove processingTime in a couple of weeks
      format.json { render json: { files: overview_files, processingTime: 0 } }
    end
  end


  private

  def should_subdirectory?
    # If we request a JSON, it's from the Code View and we want the payload of the root folder,
    # we're not looking for the overview page. We just want to render the root in the Code View.
    return true if request.headers["Accept"] == "application/json"

    !current_path.blank? || params[:files] == "1" || params[:search] == "1" || (params[:name] =~ /\// && params[:name] != params[:branch])
  end

  def current_layout
    if @rendering_react_view
      "layouts/repository_with_container"
    else
      "repository"
    end
  end

  def blob_redirect(exception = nil)
    s_tree = escape_url_branch(tree_name)
    if exception.is_a?(GitRPC::InvalidObject)
      s_path = escape_url_paths(current_path)
      redirect_to "/#{current_repository.name_with_display_owner}/blob/#{s_tree}/#{s_path}",
      status: 301
    elsif current_path.size > 1
      s_path = escape_url_paths(current_path.parent)
      redirect_to "/#{current_repository.name_with_display_owner}/tree/#{s_tree}/#{s_path}",
      status: 301
    else
      render_404
    end
  end

  def raw_redirect
    if params[:raw]
      url = request.url
      if url.include?(".git") && !url.include?(".git/")
        redirect_to url.sub(".git", ".git/")
        true
      end
    end
  end

  def ensure_commit_sha
    begin
      if commit_sha.blank? || current_commit.nil?
        if database_errors.length > 0
          @render_database_error = true
        elsif custom_codeview_404?(true) && (should_subdirectory?)
          @render_codeview_404 = true
        else
          render_404
        end
      end
    rescue GitRPC::BadObjectState
      raise
    rescue GitRPC::Error
      if custom_codeview_404?(true) && (should_subdirectory?)
        @render_codeview_404 = true
      else
        render_404
      end
    end
  end

  def ref
    params[:ref] || params[:name]
  end

  def route_supports_advisory_workspaces?
    true
  end

  def app_payload
    Repos::ReactPayload.app_payload(find_file_worker_path, find_in_file_worker_path, github_dev_enabled?)
  end

  def page_title
    if should_subdirectory?
      "#{current_repository.name}/#{path_string_for_display} at #{tree_name_for_display} · #{current_repository.name_with_display_owner}"
    else
      with_database_error_fallback(fallback: "#{current_repository.name_with_display_owner}") do
        Files::OverviewPageTitle.new(
          ref: ref,
          repository: current_repository,
          logged_in: logged_in?,
        )
      end
    end
  end

  def contributor_users(contributors, repo)
    commit_count_by_email = Hash[contributors.map { |c| [c["author"].downcase, c["count"]] }]
    business = repo.enterprise_managed_business if repo.is_enterprise_managed?
    contributor_emails = contributors.map { |c| c["author"] }

    users = {}
    User.find_by_emails(contributor_emails, business: business).each do |email, user|
      # It's possible that we can get a user with an email address
      # that does not match any of the email addresses from GitRPC
      # due MySQL collation matching and returning users for email
      # addresses that are slightly different than the address we
      # queried for.
      #
      # For example, querying for
      #   aurélien.alriquet@devinci.fr
      # can return a user with an email address of
      #   aurelien.alriquet@devinci.fr
      #
      # but the strings will not match in Ruby.
      #
      # I think these are actually different email addresses
      # in practice, so this kind of "fuzzy" match probably
      # shouldn't result in the user being displayed as a
      # blob contributor, even though they may very well
      # be the same person.
      #
      if user && (count = commit_count_by_email[email.downcase])
        users[user] ||= {
          id: user.id,
          login: user.display_login,
          userEmail: user.email,
          primaryAvatarUrl: avatar_url_for(user, 80),
          profileLink: user_path(user),
          commitsCount: 0,
        }

        users[user][:commitsCount] += count
      end
    end

    users.values.sort_by { |user| user[:commitsCount] }.reverse
  end

  def show_immutable_actions_migration_banner?(migration_enabled, release_tags, migration_status)
    return false unless migration_enabled
    return false unless current_repository.actions.discoverable.any?
    return false unless current_repository.resources.packages.writable_by?(current_user)
    return false unless release_tags.any?
    return false if migration_status == MigrateSemverReleasesToImmutableActionsJob::MIGRATION_COMPLETED
    true
  end
end
