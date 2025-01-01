# typed: true
# frozen_string_literal: true

class TreeController < GitContentController
  map_to_service :star, only: [:star, :unstar] # rubocop:todo GitHub/MapToService

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:find]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:archive]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Billing,
    only: [:tarball]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:zipball]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:fork_select]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::TokenScanningService,
    ApplicationRecord::Notify,
    only: [:delete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Pages,
    only: [:show_partial]

  depends_on_clusters ApplicationRecord::Copilot, only: [
    :fork_select,
    :tarball,
    :delete,
    :find,
    :show_partial,
    :zipball,
    :list
  ], optional: true

  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(
    archive tarball zipball show_partial find
    list star unstar fork_select fork
  ).freeze

  FORK_LIST_LIMIT = 100

  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::TextHelper
  include BranchesHelper
  include Repos::CodeViewHelper
  include Repos::TreePayloadHelper
  include ShowPartial
  include GitRPC::Util
  include WebCommitControllerMethods
  include CommitHelper
  include Repos::OwnerRepoSelectionsPayloadHelper
  include RepositoriesDefaultSelectionHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :clean_params, only: [:delete, :destroy]
  skip_before_action :ask_the_gitkeeper, only: [:star, :unstar, :check]
  skip_before_action :ask_the_gatekeeper, only: [:unstar]
  skip_before_action :authorization_required, only: [:unstar]
  before_action :login_required, only: [:star, :unstar, :destroy]
  before_action :redirect_delete_to_show, only: [:delete]
  before_action :login_required_redirect_for_public_repo, only: [:delete, :fork, :fork_select]
  before_action :content_authorization_required, only: [:delete, :destroy, :fork, :fork_select]
  before_action :require_tree, only: [:delete, :destroy]
  before_action :confirm_forking, only: [:delete]
  before_action :require_repository_not_migrating, only: [:delete]
  layout "repository"
  javascript_bundle :repositories
  stylesheet_bundle :code

  allow_verified_fetch only: [:fork, :star, :unstar]

  def delete # rubocop:todo GitHub/UseRestfulActions
    path = path_string
    @branch = tree_name

    web_commit_form_url = destroy_directory_path(current_repository.owner, current_repository, @branch, path, pr: params[:pr])

    if code_view_enabled?
      GitHub.dogstats.increment("repos-react-migration.react", tags: dogstats_request_tags)

      # Serve json if soft-nav
      request&.format = :json if json_request?

      add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)
      add_csrf_token(web_commit_form_url, :delete)

      file_tree, file_tree_processing_time, folders_to_fetch = ascend_tree(current_path)

      commit_oid = current_repository.refs[@branch]&.target_oid

      web_commit_info = web_commit_info(commit_oid, web_commit_form_url, @branch)
      return render_404 if web_commit_info == false

      all_shortcuts_enabled = current_user&.settings&.get(:keyboard_shortcuts_preference) == "all"

      return render_404 unless set_form_commit

      synthetic_commit = current_repository.create_commit(@last_commit,
          message: "Temporary Commit for Preview",
          author: current_user,
          files: { "#{current_tree.path}" => nil },
          skip_rule_evaluation: true,
        )

      synthetic_commit.set_diff_options(max_files: 1000)

      diffs = synthetic_commit.diff

      diffs.record_diff_metrics(params: params, dogstats_request_tags: dogstats_request_tags + dogstats_staff_request_tags)

      diffs_paylod = diffs.map.with_index do |diff, index|
        base_user = current_repository.owner_display_login if diffs.repo != current_repository
        head_user = @forked_repo.owner_display_login if diffs.repo != @forked_repo && @forked_repo.present?

        options = {
          entry: index,
          base_user: base_user,
          head_user: head_user,
          w: diffs.ignore_whitespace?,
          sha1: diffs.parsed_sha1,
          sha2: diffs.parsed_sha2,
          base_sha: diffs.base_sha,
          name: current_repository.default_branch
        }

        {
          deletions: diff.deletions,
          path: diff.a_path,
          loadDiffPath: diff_path(current_repository.owner_display_login, current_repository, options),
        }
      end

      # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
      # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
      @rendering_react_view = true

      render_react_app(
        title:  "Deleting #{current_repository.name_with_display_owner} at #{h tree_name_for_display}",
        app_payload_generator: -> { app_payload },
        app_name: "react-code-view",
        payload: lambda do
          {
            allShortcutsEnabled: all_shortcuts_enabled,
            fileTree: file_tree,
            fileTreeProcessingTime: file_tree_processing_time,
            foldersToFetch: folders_to_fetch,
            repo: Repos::ReactPayload.current_repository_payload(
              current_repository,
              current_user_can_push: current_user_can_push?
            ),
            refInfo: {
              name: tree_name,
              listCacheKey: ref_list_cache_key,
              canEdit: true,
              refType: helpers.tree_type,
              currentOid: commit_sha
            },
            currentUser: Repos::ReactPayload.current_user_payload(current_user),
            deleteInfo: {
             diffs: diffs_paylod,
             isBlob: false,
             truncated: diffs.truncated?
            },
            webCommitInfo: web_commit_info,
            path: path_string,
          }
        end,
        page_data: { selected_link: :repo_source, send_vitals: true },
        turbo: {
          id: "repo-content-turbo-frame",
          target: "_top",
          action: "advance",
          class: full_height? ? "d-flex flex-auto" : ""
        },
        disable_ssr: !GitHub.flipper[:react_blob_ssr].enabled?(current_user),
      )
    else
      GitHub.dogstats.increment("repos-react-migration.rails", tags: dogstats_request_tags)

      return render_404 unless establish_target_repository(branch: @branch, create_fork: request&.post?, update_fork: request&.post?)
      return render_404 unless set_form_commit

      tree_delete_view_attrs = {
        branch: @branch,
        current_tree: current_tree,
        forked_repo: @forked_repo,
        forked_reason: @forked_reason,
        last_commit: @last_commit,
        parent_repo: current_repository,
        path: path,
        quick_pull: params[:quick_pull],
        target_branch: params[:target_branch],
      }

      view = create_view_model(Tree::DeleteView, tree_delete_view_attrs)
      render "tree/delete", locals: {
        web_commit_form_url: web_commit_form_url,
        view: view,
      }
    end
  end

  def destroy
    return redirect_to(url_for(action: "delete")) unless request&.delete?

    path = path_string
    branch = tree_name
    return render_404 unless establish_target_repository(branch: branch, create_fork: false, update_fork: true)

    ref = @target_repo.heads.find(branch)
    return render_404 unless ref

    increment_quick_pull_start_stats

    if @target_repo != current_repository
      params[:quick_pull] ||= [current_repository.owner.display_login, branch].join(":")
    end

    if change_conflict?(current_tree.path, params[:commit], ref.target_oid)
      increment_quick_pull_error_stats
      return render(json: { data: { error: flash.now[:error] }, code: 422 }, status: :unprocessable_entity) if code_view_enabled?
      return delete
    end

    message = commit_message_from_request("delete")

    # In order to allow the repository rules engine to delineate between the deletion of a file and a directory, we rely on an appended path separator.
    files = { "#{current_tree.path}/" => nil }

    new_commit_sha, branch, hook_error = commit_change_to_repo_for_user(@target_repo, current_user, branch, params[:commit], files, message)

    unless branch
      violations = []
      if hook_error
        @hook_message = "Directory could not be deleted."
        flash.now[:error] = "Directory could not be deleted."
        if hook_error.include?("Repository rule violations found")
          hook_error = hook_error.strip.split("\n\n")
          violations = hook_error[1..-1]
          flash.now[:error] = "Please address the rule violations and try again."
        end
      else
        flash.now[:error] = "Directory could not be deleted."
      end

      increment_quick_pull_error_stats
      if code_view_enabled?
        return render(json: { data: { error: flash.now[:error], error_details: { ruleViolations: violations } }, code: 422 }, status: :unprocessable_entity)
      end
      return delete
    end

    increment_quick_pull_commit_stats

    message = nil
    commit_quorum_poll_path = check_commit_quorum_path(new_commit_sha)

    if params[:quick_pull]
      # redirect to new pull request page
      base = params[:quick_pull]
      base = nil if base == "1"
      range = [base, branch].compact.join("...")
      pull_type = @target_repo.fork? ? "" : "?quick_pull=1"

      redirect_url = compare_path(@target_repo, range) + pull_type
    elsif redirect_back_to_pr?
      redirect_url = "#{redirect_back_to_pr_url}/files##{diff_path_anchor(path)}"
    else
      # redirect to parent directory
      message = "Directory successfully deleted."
      redirect_path = current_repository.longest_existing_subpath(path, branch)
      redirect_path = nil if redirect_path.empty?
      redirect_url =  tree_url(name: branch, path: redirect_path)
    end

    if code_view_enabled?
      render(json: { data: { redirect: redirect_url, message: message, commitQuorumPollPath: commit_quorum_poll_path } }, status: :ok)
    else
      flash[:notice] = message if message.present?
      redirect_to redirect_url
    end
  end

  def check # rubocop:todo GitHub/UseRestfulActions
    if current_repository.nil? || !current_repository.ready_for_writes?
      head 202
    else
      head :ok
    end
  end

  param_encoding :find, :name, "ASCII-8BIT"

  def find # rubocop:todo GitHub/UseRestfulActions
    return render_404 if tree_sha.nil?

    render "tree/find"
  end

  def list # rubocop:todo GitHub/UseRestfulActions
    expires_in 1.day
    if stale? etag: params[:name]
      if valid_full_oid?(params[:name])
        time_key = "repos.tree_list.time"
        tags = ["include_directories: #{params[:include_directories]}"]
        GitHub.dogstats.distribution_time(time_key, tags: tags) do
          if params[:include_directories] == "true"
            paths = current_repository.tree_file_list(params[:name], list_directories: true, return_separate_lists: true)
            render json: { paths: paths[:files], directories: paths[:directories] }
          else
            paths = current_repository.tree_file_list(params[:name])
            render json: { paths: paths }
          end
        end
      else
        render status: 400, json: { paths: [] }
      end
    end
  end

  def dismiss_tree_finder_help # rubocop:todo GitHub/UseRestfulActions
    current_user&.dismiss_notice("tree_finder_help")

    if request&.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  def fork # rubocop:todo GitHub/UseRestfulActions
    # check if an organization login has been sent
    org_login = if !params[:owner].blank? && (params[:owner] != current_user&.name)
      params[:owner]
    elsif !params[:organization].blank?
      params[:organization]
    else
      nil
    end

    if org_login
      org = Organization.find_by_login(org_login)
      unless required_external_identity_session_present?(target: org)
        render_external_identity_session_required(target: org)
        return
      end
    end

    description = params.dig(:fork_repository, :description)

    unless params.dig(:fork_repository, :name).blank?
      new_name = params[:fork_repository][:name]
    end

    one_branch_fork = params.dig(:fork_repository, :one_branch_fork) == "1"

    forked, reason, errors = current_repository.fork(org: org, forker: current_user, description: description, new_name: new_name, one_branch: one_branch_fork)

    tags = ["form:fork"]
    tags << "one_branch_fork:#{one_branch_fork}"
    tags << "error:#{errors.present?}"
    GitHub.dogstats.increment("repos_form_submit", tags: tags)

    if forked
      GitHub.dogstats.increment("repo", tags: ["action:fork", "valid:true"])
      redirect_to clean_repository_path(forked)
    else
      GitHub.dogstats.increment "repo", tags: ["action:fork", "valid:false", "error:#{reason}"]
      Failbot.report_user_error Repository::NetworkDependency::ForkFailure.new,
        "gh.org.name": params[:organization], "gh.repo.id": current_repository.id,
        "gh.repo.fork.failure_reason": reason

      flash[:error] = Repository::ForkerMethods.message_from_reason(reason, errors)

      redirect_to current_repository.permalink
    end
  end

  # The "Where do you want to fork this to?" dialog that pops up when you hit
  # fork. This is loaded in via Ajax when the Fork button is clicked because
  # calculating the fork existence and permissions for each organization on each
  # repository page hit is very expensive.
  def fork_select # rubocop:todo GitHub/UseRestfulActions
    return redirect_to_login(url_for) unless logged_in?

    return forking_disabled_redirect if current_repository.forking_disabled?

    payload = GitHub.dogstats.distribution_time("repos_form.payload.time", tags: ["form:fork"]) do
      owner_items = initial_owner_items_payload(cap_filter, T.must(current_user), current_repository)
      # Current org is usually not the best choice for the fork.
      # Therefore, if we can be certain that user are allowed to fork we suggest user as the initial owner.
      initial_owner = if owner_items
        user_as_owner = owner_items.first
        user_can_fork = user_as_owner && user_as_owner[:name] == current_user&.display_login && !user_as_owner[:disabled]
        user_can_fork ? initial_owner_selection_payload(current_user, T.must(current_user)) : nil
      else
        # The request is deferred and we cannot reliably suggest an initial owner.
        nil
      end

      # We show list only if owner items load is not deferred.
      # Otherwise checking if there are any available options might be too expensive.
      no_available_targets_to_fork = owner_items && owner_items.all? { |hash| hash[:disabled] }

      if no_available_targets_to_fork
        existing_forks = Repos::ForkFormHelper.all_existing_forks(T.must(current_user), current_repository).map do |fork|
          {
            name: fork.name,
            ownerLogin: fork.owner_display_login,
          }
        end

        {
          existingForks: existing_forks.first(FORK_LIST_LIMIT),
          truncated: existing_forks.size > FORK_LIST_LIMIT,
          repo: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
        }
      else
        {
          repoCreate: Repos::ReactPayload.repo_create_payload(owner_items, cap_filter, current_user),
          initialOwnerSelection: initial_owner,
          repoHasForks: current_repository.network_count > 0,
          repoDescription: current_repository.description,
          repo: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
        }
      end
    end

    add_csrf_token(repository_check_name_path, :post)
    render_react_app(
      title: "Fork #{current_repository.name_with_display_owner}",
      app_name: "repo-creation",
      payload: payload,
      page_data: {
          send_vitals: true,
          selected_link: :repo_source,
         },
      disable_ssr: !feature_enabled_globally_or_for_current_user?(:repos_forms_ssr),
    )
  end

  def tarball # rubocop:todo GitHub/UseRestfulActions
    current_repository ? codeload("legacy.tar.gz".dup) : render_404
  end

  def zipball # rubocop:todo GitHub/UseRestfulActions
    current_repository ? codeload("legacy.zip".dup) : render_404
  end

  def archive # rubocop:todo GitHub/UseRestfulActions
    current_repository ? codeload(params[:_format]) : render_404
  end

  def codeload(type) # rubocop:todo GitHub/UseRestfulActions
    unless meets_oauth_application_policy_for_current_repo?
      render_404
      return
    end

    unless current_repository.public?
      current_repository.instrument(:download_zip, download_zip_context)
    end

    # Historically, only tree_name was used and params[:path] ignored. It's
    # useful to control the filename of downloads in clients that ignore the
    # Content-Disposition header.
    #
    #  https://github.com/{OWNER}/{PROJECT}/archive/{COMMIT}/{FILENAME}.tar.gz
    #
    # But later we started using
    #
    #  https://github.com/{OWNER}/{PROJECT}/archive/{BRANCH_OR_TAG_NAME}.tar.gz
    #
    # instead, which has namespacing issues. We've now moved to
    #
    #  https://github.com/{OWNER}/{PROJECT}/archive/{REFNAME}.tar.gz
    #
    # to avoid that. Inadvertently another version
    #
    #  https://github.com/{OWNER}/{PROJECT}/archive/{TAG_NAME}/{FILENAME}.tar.gz
    #
    # became a de-facto API used in many scripts, so we also need to support that.
    #
    # Unfortunately this controller will try to guess what we
    # mean with the path and split such a refname, which means
    # branch_to_codeload needs to take care to support all the different modes.
    ac = current_repository.archive_command(branch_to_codeload, type)
    url = ac.codeload_url(current_user)
    expires_in 0.seconds # make sure nothing caches the redirect url (e.g. heroku)
    redirect_to url
  rescue GitRepository::ArchiveCommand::RefnameConflictError => e
    message = "the given path has multiple possibilities: #{e.variants.join(", ")}"
    render status: 300, plain: message
  end

  def hash_or_branch(path) # rubocop:todo GitHub/UseRestfulActions
    return path if GitRPC::Util.valid_full_oid?(path)

    if qualified = GitRepository::ArchiveCommand.qualified_name_from_revision(current_repository, path)
      return qualified
    end

    # This last check is to see if the caller is asking for 'master' but we
    # don't have that. If the feature flag is on, we redirect to the default branch
    path = path.delete_prefix("refs/heads/")
    result = RepositoryBranchRename::Detector.call(repository: current_repository, full_path: path, all_possible_names: false)
    result.redirect_branch if result.includes_renamed_branch?
  end

  def branch_to_codeload # rubocop:todo GitHub/UseRestfulActions
    # The path given in the URL may contain a filename as its last component
    # meant to override the filename client-side. We need to figure out which
    # variant this is by first trying to find the full path as a ref and then
    # skipping the last component.

    # Take the entire thing to start with
    path = [params[:name], *params[:path]].join("/")


    # Is the whole thing a ref we can see
    if branch = hash_or_branch(path)
      return branch
    end

    # What about without the last bit? Return early if we don't have anything
    # more
    shortened, _, _ = path.rpartition("/")
    return path if shortened.blank?

    if branch = hash_or_branch(shortened)
      return branch
    end

    # As a last resort, pass along the input to maintain compatibility
    path
  end

  def star # rubocop:todo GitHub/UseRestfulActions
    authorization = ContentAuthorizer.authorize(current_user, :star, :create, starrable: current_repository)

    if authorization.failed?
      if request&.xhr?
        render status: :unprocessable_entity, json: { error: authorization.error_messages }
      else
        flash[:error] = authorization.error_messages
        redirect_to :back
      end
    else
      Stars.domain.star_repository(user: T.must(current_user), repository: current_repository, context: params[:context] || "")
      GitHub.dogstats.increment("stars.star")

      respond_to do |wants|
        wants.json { render json: { count: star_count } }
        wants.html { redirect_to :back }
      end
    end
  end

  def unstar # rubocop:todo GitHub/UseRestfulActions
    # Users should be able to unstar a disabled repo so we skip the gatekeeper
    # before filter and do it ourselves.
    #
    # The permissions check is done here instead of in the service object so that we can take advantage of a
    # previously memoized result.
    if current_repository.nil? || !current_user_can_read_repo?
      return render_404
    end

    result = Stars::UnstarService.call(
      repository: current_repository,
      actor: current_user,
      context: params[:context],
      confirm: params[:confirm],
    )

    if result.success?
      respond_to do |wants|
        wants.json { render json: { count: star_count } }
        wants.html { redirect_to :back }
      end
    elsif result.unconfirmed?
      respond_to do |wants|
        wants.json do
          # Dialog inputs match the expected {{ parts }} in the template identified by the CSS selector, rendered by the
          # component found at `app/components/user_lists/unstar_dialog_template_component.html.erb`.
          payload = {
            count: star_count,
            confirmationDialog: {
              templateSelector: ".js-unstar-confirmation-dialog-template",
              inputs: {
                repoNameWithOwner: current_repository.name_with_display_owner,
                listsWithCount: pluralize(result.list_count, "list"),
              }
            }
          }
          render status: :conflict, json: payload
        end

        wants.html do
          redirect_to :back, flash: { error: "You must remove this repository from your lists to unstar it" }
        end
      end
    else
      # This shouldn't happen :tm:
      # If you see this error in Sentry, it's because this if-else ladder is out of sync with the possible result states
      # in Stars::UnstarService.
      raise "Unexpected result state: #{result.error_kind}"
    end
  end

  # TODO: this is only used for _recently_touched_branches_list, it could be renamed appropriately
  def show_partial # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless params[:partial] == "tree/recently_touched_branches_list"

    respond_to do |format|
      format.html do
        render partial: "tree/recently_touched_branches_list", layout: false
      end
    end
  end

  private

  def download_zip_context
    context = {}

    if logged_in?
      if current_user&.oauth_access
        scopes_string = T.must(current_user).oauth_access.scopes_string
        token_id = T.must(current_user).oauth_access.id

        context[:oauth_scopes] = scopes_string
        context[:oauth_access_id] = token_id
        context[:token_id] = token_id
        context[:token_scopes] = scopes_string
      elsif current_user&.programmatic_access
        token_id = T.must(current_user).programmatic_access.id

        context[:user_programmatic_access_id] = token_id
        context[:user_programmatic_access_name] = T.must(current_user).programmatic_access.name
        context[:token_id] = token_id
      end
    end

    context
  end

  def show_checks_status?
    return true if GitHub.actions_enabled? && cap_filter.authorized_resources([current_repository]).any?
    false
  end

  def redirect_delete_to_show
    # The "delete" part of the URL may not be an action but a legit part of the ref name. Let's try and redirect if so
    if !current_tree
      branch, path, qualified_ref = ref_sha_path_extractor.call("delete/#{params[:name]}")

      if branch
        redirect_to "/#{current_repository.name_with_display_owner}/tree/#{qualified_ref}/#{path}", status: 301
      end
    end
  end

  def require_tree
    render_404 unless current_tree
  end

  # Sets current tree based on current user and given path.
  #
  # For quick pulls only, if the current repository is a fork and the given path
  # doesn't exist in the fork, then we'll fallback to retrieving it from the original
  # base repo. This allows users to re-use their existing forks for new quick pulls.
  #
  # Returns TreeEntry (guaranteed to be type "tree") or nil if missing current commit or path
  def current_tree # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_tree if defined?(@current_tree)

    @current_tree = nil
    return @current_tree if current_commit.blank? || path_string.blank?

    @current_tree = current_repository.tree(tree_sha, path_string)
    return @current_tree unless !@current_tree && params[:quick_pull]

    base_repository, base_branch = base_repository_and_branch
    base_oid = base_repository.heads.find(base_branch).target_oid
    @current_tree = base_repository.tree(base_oid, path_string)
  end

  # Default commit message for use as a placeholder in the web commit form and
  # server-side fallback if user doesn't supply a commit message.
  #
  # Overrides WebCommitControllerMethods#commit_message_placeholder.
  #
  # Returns UTF-8 String
  def commit_message_placeholder(_action)
    "Delete #{path_string_for_display} directory"
  end

  def archive_action?
    %w{archive tarball zipball}.include?(action_name)
  end

  def authentication_methods
    set_path_and_name
    if user = super
      GitHub.dogstats.increment "auth", tags: ["action:archive", "type:session"]
    elsif archive_action? && user = login_from_authorization_header_auth
      type = if user.using_oauth_application?
        "token"
      elsif user.using_oauth?
        "personal_access_token"
      else
        "password"
      end
      GitHub.dogstats.increment "auth", tags: ["action:archive", "type:#{type}"]
    end
    user
  end

  def meets_oauth_application_policy_for_current_repo?
    OauthApplicationPolicy::HttpRequest.new(
      repository: current_repository,
      user: current_user,
      request: request,
    ).satisfied?
  end

  def content_authorization_required
    return false if rendering_modal_fork_selector?

    if %w[delete destroy].include?(action_name)
      authorize_content(:blob)
    else
      authorize_content(:repo)
    end
  end

  def rendering_modal_fork_selector?
    # Block the full-page fork_select screen, but allow the modal version.
    action_name == "fork_select" && (request&.xhr? || params[:fragment].to_i == 1)
  end

  # Bypassing conditional access for show_partial also requires that
  # the partial is exempted.
  def conditional_access_exempt?
    super && (action_name != "show_partial" || conditional_access_exempt_partial?(params[:partial]))
  end

  # Overrides before filter `require_active_external_identity_session` from
  # controllers/application_controller/external_sessions_dependency.rb
  #
  # For legacy routes that allow basic authentication we can't support SAML SSO
  # as there is no associated user_session from which to find external
  # identity sessions.
  def require_active_external_identity_session
    return true unless organization_saml_enforced?

    case authorization_header_auth_status
    when :active_credential_authorization; true
    when :no_active_credential_authorization; head :forbidden
    else
      # Fallback to the default implementation when the current user is not
      # using basic auth.
      super
    end
  end

  def organization_saml_enforced?
    target = safe_target_for_conditional_access
    return false if target == :no_target_for_conditional_access

    policy = saml_enforcement_policy_for(target)
    return false if policy.nil?
    policy.enforced?
  end

  def authorization_header_auth_status
    return unless authorization_header_authed?

    if active_credential_authorization?
      :active_credential_authorization
    else
      :no_active_credential_authorization
    end
  end

  def active_credential_authorization?
    if logged_in? && current_user&.using_oauth?
      target = safe_target_for_conditional_access
      return false if target == :no_target_for_conditional_access
      # Using personal access token
      credential_authorization = Organization::CredentialAuthorization.by_organization_credential(
        organization: target,
        credential: current_user&.oauth_access,
      ).first

      credential_authorization && credential_authorization.active?
    end
  end

  def star_count
    # This uses the formatting logic from the Primer::Beta::Counter. That way
    # this returned string matches the string we use when initially rendering
    # the HTML with the Primer::Beta::Counter.
    units = { thousand: "k", million: "m" }
    number_to_human(current_repository.stargazer_count, precision: 1, significant: false, units: units, format: "%n%u")
  end

  def route_supports_advisory_workspaces?
    !%w[fork fork_select].include?(action_name)
  end

  def employee?
    logged_in? && current_user&.employee?
  end

  def protected_org_logins_payload
    protected_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
    if protected_org_ids.any?
      Organization.where(id: protected_org_ids).pluck(:login)
    end
  end

  def forking_disabled_redirect
    flash[:error] = "Forking is disabled for this repository."
    redirect_to repository_url(current_repository)
  end

  def app_payload
    Repos::ReactPayload.app_payload(find_file_worker_path, find_in_file_worker_path, github_dev_enabled?)
  end
end
