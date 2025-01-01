# typed: true
# frozen_string_literal: true

class BranchesController < GitContentController
  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  include GitHub::UTF8
  include BranchesHelper
  include Repos::BranchesViewDependency
  include Repos::CodeViewHelper

  allow_verified_fetch only: [:create, :update, :check_tag_name_exists, :fetch_and_merge, :deferred_metadata, :rename_ref_check, :destroy]
  sig { returns(String) }
  def self.react_bundle_name
    "repos-branches"
  end

  before_action :pushers_only,    only: [:create, :destroy, :update]

  skip_before_action :set_path_and_name

  layout :current_layout
  javascript_bundle :repositories
  stylesheet_bundle :code

  param_encoding :destroy, :name, "ASCII-8BIT"
  param_encoding :rename_form, :name, "ASCII-8BIT"
  param_encoding :update, :name, "ASCII-8BIT"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Pages,
    only: [:rename_form]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Configurations,
    only: [:source_branch]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:target_repositories]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:delete_branch_dialog]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:check_tag_name_exists]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:pre_mergeable]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:all]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:active]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:stale]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:yours]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :yours, :active, :stale, :all],
    optional: true

  def index
    render_branches_page(:overview)
  end

  def yours # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in?

    render_branches_page(:yours, params[:page].to_i)
  end

  def active # rubocop:todo GitHub/UseRestfulActions
    render_branches_page(:active, params[:page].to_i)
  end

  def stale # rubocop:todo GitHub/UseRestfulActions
    render_branches_page(:stale, params[:page].to_i)
  end

  def all # rubocop:todo GitHub/UseRestfulActions
    render_branches_page(:all, params[:page].to_i, params[:query].to_s)
  end

  def deferred_metadata # rubocop:todo GitHub/UseRestfulActions
    branch_names = JSON.parse(request&.body.read || "{}")["branches"] || []
    return {} if branch_names.empty?

    render json: {
      deferredMetadata: branches_metadata(
        branch_names,
        include_authors: params[:include_authors] == "true"
      )
    }
  end

  # Renders a "refs/selector" as part of the create branch for issue dialog.
  def source_branch # rubocop:todo GitHub/UseRestfulActions
    repository = Repositories::Public.find_active!(params[:branch_repository_id])
    return render_404 unless repository.readable_by?(current_user)
    render(Branch::SourceBranch::BranchSelectComponent.new(repository: repository), layout: false)
  end

  def target_repositories # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in?
    render Branch::TargetRepositoryComponent.new(
      query: query,
      selected_repository: current_repository,
      current_repository: current_repository
    ), layout: false
  end

  private def query
    Branches::TargetRepositoryQuery.new(
      selected_repository: current_repository,
      current_user: current_user,
      phrase: params[:q],
      user_session: user_session,
      remote_ip: request&.remote_ip,
      cap_filter: cap_filter,
      user_repos_first: true
    )
  end

  def update
    unless current_repository&.branch_renameable_by?(current_user, branch: params[:name])
      if request&.format&.json?
        return render json: { error: "Not found" }, status: 404
      end
      return render_404
    end

    ref = T.must(current_repository).heads.find(params[:name])
    unless ref&.exist?
      if request&.format&.json?
        return render json: { error: "Not found" }, status: 404
      end
      return render_404 unless ref&.exist?
    end

    renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: T.must(current_repository), branch_name: params[:name])
    old_name_for_display = utf8(renamer.old_name.dup)

    new_name = if request&.format&.json?
      body = JSON.parse(request&.body&.read)
      body["new_name"]
    else
      params[:new_name]
    end

    if renamer.start_rename(new_name, actor: T.must(current_user), entry_point: :branches_controller_update)
      new_name_for_display = utf8(renamer.rename&.new_name.dup)
      message = "Branch #{old_name_for_display} will be renamed to #{new_name_for_display} shortly."
      if request&.format&.json?
        return render json: { message: message }, status: 200
      end
      flash[:notice] = message
    else
      if renamer.rename&.started? && !renamer.rename&.new_record?
        GitHub.logger.info(
          "Fixed Rename stuck in starting state",
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repo.id" => T.must(current_repository).id,
          "gh.branch_protection_rule.repository_branch_renamer.id" => renamer.rename&.id,
          "gh.branch_protection_rule.repository_branch_renamer.human_error" => renamer.human_error
        )
        renamer.rename&.errored!
      end
      error = "Could not rename branch \"#{old_name_for_display}\" at this time:" \
      " #{renamer.human_error}"
      if request&.format&.json?
        return render json: { error: error }, status: 422
      end
      flash[:error] = error
    end

    redirect_to branches_path(current_repository)
  end

  def create
    name = Git::Ref.normalize(params[:name])
    repo = params.has_key?(:repo) && params[:repo].present? ? Repositories::Public.find_active!(params[:repo]) : nil
    commit_oid = T.let(nil, T.nilable(String))
    if repo && current_repository&.parent&.id == repo.id
      parent_repo = T.cast(T.must(current_repository).parent, Repository) # rubocop:todo GitHub/AvoidCast
      commit_oid = T.must(parent_repo).ref_to_sha(params[:branch])
    else
      commit_oid = current_repository&.ref_to_sha(params[:branch])
    end
    has_after_create_param = params.has_key?(:after_create)
    skip_error_flash = params.has_key?(:skip_error_flash)
    show_recreate_flash = params.has_key?(:show_recreate_flash)
    send_response_as_json = params.has_key?(:send_response_as_json)
    error_message = nil

    if !request&.xhr?
      if name.blank?
        flash[:error] = "Sorry, the branch cannot be blank."
        redirect_to params[:return_to] || :back
        return
      elsif commit_oid.nil? || (repo && !repo.readable_by?(current_user))
        flash[:error] = "Sorry, the branch #{name} could not be created."
        redirect_to params[:return_to] || :back
        return
      end
    end

    if request&.xhr?
      if name.blank?
        return render json: { error: "Sorry, the branch cannot be blank." }, status: 400 if is_react_request?(request) || send_response_as_json
        return render Branch::CreateErrorComponent.new(message: "Sorry, the branch cannot be blank."), layout: false, status: 400
      elsif commit_oid.nil? || (repo && !repo.readable_by?(current_user))
        return render json: { error: "Sorry, the branch #{name} could not be created." }, status: 400 if is_react_request?(request) || send_response_as_json
        return render Branch::CreateErrorComponent.new(message: "Sorry, the branch #{name} could not be created."), layout: false, status: 400
      end
    end

    branch_exists = false
    success =
      begin
        T.must(current_repository).heads.create(name, commit_oid, current_user,
                                        reflog_data: request_reflog_data("web branch create"))
      rescue Git::Ref::ExistsError
        error_message = "Sorry, that branch already exists."
        flash[:error] = error_message unless skip_error_flash
        branch_exists = true
        false
      rescue Git::Ref::HookFailed => e
        error_message = "Branch could not be created."
        flash[:hook_out] = e.message
        flash[:hook_message] = error_message
        false
      rescue Git::Ref::InvalidName, Git::Ref::UpdateFailed
        error_message = "Sorry, that branch name is invalid."
        flash[:error] = error_message unless skip_error_flash
        false
      rescue Git::Ref::ProtectedBranchUpdateError => e
        error_message = "Create #{e.message}"
        flash[:error] = error_message unless skip_error_flash
        false
      rescue Git::Ref::RepositoryRuleViolationError => e
        error_message = e.detailed_message
        flash.now[:error] = error_message unless skip_error_flash
        false
      else
        GitHub.instrument "branch.create", user: current_user
        true
      end

    if has_after_create_param
      tag = %w[checkout-locally github-desktop].include?(params[:after_create]) ? params[:after_create] : nil

      GitHub.dogstats.increment("branch.created", tags: ["source:web", "after_create:#{tag}"])

      if params[:after_create] == "checkout-locally"
        render Branch::LocalCheckoutComponent.new(branch_name: name), layout: false
      else
        render Branch::OpenInDesktopComponent.new(branch_name: name, repository: current_repository), layout: false
      end
      return
    end

    if is_react_request?(request) || send_response_as_json
      return render json: { error: error_message }, status: 422 if !success && !skip_error_flash

      channel = live_update_view_channel(GitHub::WebSocket::Channels.branch(current_repository, name))

      return render json: {
        name:,
        channel:,
      }, status: 200 if success
    end
    if request&.xhr?
      return render Branch::CreateErrorComponent.new(message: error_message), layout: false, status: 422 if !error_message.nil?
      render plain: success ? "Branch #{name} will be created shortly." : nil, status: success ? 200 : 422
      flash[:notice] = "Branch #{name} has been created and will appear shortly." if show_recreate_flash
    else
      if success
        flash[:notice] = "Branch created."

        path_binary = params[:path_binary]
        raw_path = Base64.decode64(path_binary).b if path_binary
        branch_path = tree_path(raw_path, name, current_repository)

        redirect_to params[:return_to] || branch_path
      else
        redirect_to params[:return_to] || :back
      end
    end
  end

  def destroy
    ref = current_repository&.heads&.find(params[:name])

    if ref && ref.exist?
      if ref.deleteable?(deleter: current_user)
        begin
          ref.delete(current_user, reflog_data: request_reflog_data("branches page delete button"))
        rescue Git::Ref::HookFailed => e
          flash[:hook_out] = e.message
          flash[:hook_message] = "Branch could not be deleted."
          status = 422
        else
          GitHub.instrument "branch.delete", user: current_user
          status = 200
        end
      else
        flash[:error] = "Sorry, couldn’t delete that branch."
        status = 403
      end
    else
      flash[:error] = "Sorry, couldn’t delete that branch."
      status = 404
    end

    was_success = 200 == status

    if was_success && CommitContribution.track_commits_in_branch?(repository: current_repository,
                                                                  branch: ref.name)
      CommitContribution.backfill(current_repository, true)
    end

    if request&.xhr?
      head status
    else
      flash[:notice] = "Branch deleted." if was_success
      redirect_to params[:return_to] || :back
    end
  end

  # Can we merge two branches? Used on the create new pull request form.
  #
  # - params[:range] - Same style as compare URLs
  #
  # If HTML is requested, renders a partial displaying whether the branches can be merged or not.
  # If JSON is requested, its "state" key will be "clean" (mergeable), "dirty" or "error"
  def pre_mergeable # rubocop:todo GitHub/UseRestfulActions
    return head(:not_found) if params[:range].blank?

    comparison = GitHub::Comparison.from_range_or_ref(current_repository, params[:range], limit: 250, user: current_user)

    return head(:not_found) unless comparison.valid?

    GitHub.dogstats.increment("pull_requests.create_merge_commit", tags: ["location:branches_pre_mergeable", "unreachable:true"])
    merge_commit, error = if current_repository&.feature_enabled?(:pre_mergeable_discard)
      begin
        # We're explicitly skipping the other create_merge_commit code paths because we're _just_ checking for the
        # validity of git state.
        name, email = User.git_author_info(User.ghost)
        result, error, _details = comparison.compare_repository.rpc.create_merge_commit(
          comparison.base_sha,
          comparison.head_sha,
          { name:, email:, time: Time.current },
          "Test mergeability of potential pull request",
          use_tmp_objdir_mode: "discard", # Do not persist the commit to the git repo, reducing unreachable objects.
        )

        [error.nil?, error&.to_sym]
      rescue => exception # rubocop:disable Lint/GenericRescue
        Failbot.report(exception)
        [nil, :error]
      end
    else
      comparison.compare_repository.commits.create_merge_commit(
        User.ghost,
        comparison.base_sha,
        comparison.head_sha
      )
    end

    if merge_commit
      state = :clean
    elsif [:merge_conflict, :already_merged].include?(error)
      state = :dirty
    else
      state = :error
    end

    respond_to do |format|
      format.html do
        render partial: "branches/pre_mergeability", locals: { state: state }
      end
      format.json do
        GitHub.dogstats.increment("branch.json_conflict_check", tags: ["state:#{state}"])
        render json: { state: state }
      end
    end
  end

  # Endpoint for the new-branch ref check
  #
  # - params[:ref] - The proposed ref to validate.
  #
  # Sends back a normalized, unique version of the proposed ref.
  def ref_check # rubocop:todo GitHub/UseRestfulActions
    ref = params[:ref]
    return head :not_acceptable if ref.blank?

    # Normalize.
    ref = Git::Ref.normalize(ref)

    # Ensure there’s no collisions.
    if current_repository&.refs&.exist?(ref)
      # Send back `master-1` if `master` exists.
      ref = T.must(current_repository).refs.temp_name(topic: ref)
    end

    render json: {
      message_html: ref == params[:ref] ? nil : "Will be created as <span class='branch-name'>#{h(ref)}</span>",
      normalized_ref: ref, # For updating the hidden field.
    }
  end

  def rename_form # rubocop:todo GitHub/UseRestfulActions
    branch = params[:name]
    return head(:not_found) if branch.blank?
    return head(:not_found) unless current_repository&.heads&.exist?(branch)

    section = params[:section]
    branch_for_display = utf8(branch.dup)
    input_id = if section.present?
      "#{section}_branch_#{branch_for_display}_new_name"
    else
      "branch_#{branch_for_display}_new_name"
    end

    sample_rename = RepositoryBranchRename.new(repository: current_repository, old_name: branch)
    pr_retarget_count_by_repo = sample_rename.count_of_pull_requests_to_retarget_by_repo_id
    pr_closure_count = sample_rename.pull_requests_that_will_be_closed.count
    draft_release_count = sample_rename.draft_releases_to_retarget.count
    protected_branch_count = sample_rename.protected_branch_to_update.nil? ? 0 : 1
    will_pages_change = sample_rename.update_pages?

    effect_data = {
      pr_retarget_count: pr_retarget_count_by_repo.values.sum,
      pr_retarget_repo_count: pr_retarget_count_by_repo.keys.size,
      pr_closure_count: pr_closure_count,
      draft_release_count: draft_release_count,
      protected_branch_count: protected_branch_count,
      will_pages_change: will_pages_change
    }

    if react_branches_enabled? && request&.format&.json?
      render json: effect_data.transform_keys { |k| k.to_s.camelize(:lower) }, status: :ok
    else
      render partial: "branches/rename_branch_form", locals: {
        branch: branch_for_display,
        input_id: input_id,
        is_default: T.must(current_repository).default_branch == branch,
        **effect_data
      }, layout: false
    end
  end

  # Endpoint akin to #ref_check but for use with `<auto-check>` and will not suggest
  # an alternate name when the proposed branch name already exists.
  def rename_ref_check # rubocop:todo GitHub/UseRestfulActions
    current_name = params[:name]
    raw_name = if react_branches_enabled? && request&.format&.json?

      body = JSON.parse(request&.body&.read)
      body["value"]
    else
      params[:value]
    end
    normalized_name = Git::Ref.paste_safe_normalize(raw_name)

    response = if normalized_name.blank?
      {
        data: {
          message: "#{raw_name} is not a valid branch name.",
        },
        status: :unprocessable_entity
      }
    elsif normalized_name == current_name
      {
        data: {
          message: "#{normalized_name} is already the branch name.",
        },
        status: :unprocessable_entity
      }
    else
      ref = current_repository&.heads&.find(normalized_name)
      branch_exists = ref&.exist?
      if branch_exists
        {
          data: {
            message: "Branch #{normalized_name} already exists.",
          },
          status: :unprocessable_entity
        }
      else
        {
          data: {
            message: "Your branch name will be #{normalized_name}",
            normalized_name: normalized_name
          }
        }
      end
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "branches/rename_ref_check", locals: {
          message: response[:data][:message],
          normalized_name: response[:data][:normalized_name]
        }, formats: :html, status: response[:status] || :ok
      end

      if react_branches_enabled?
        format.json do
          render json: {
            **response[:data],
          }, status: response[:status] || :ok
        end
      end
    end
  end

  # Updates a branch in a fork by fetching new commits from the base and merging
  # them into the branch (as long as there are no conflicts)
  def fetch_and_merge # rubocop:todo GitHub/UseRestfulActions
    discard_changes = params[:discard_changes].present?
    return render_404 unless logged_in?
    ref = current_repository&.heads&.find(params[:name])
    return render_404 unless ref

    begin
      result = ref.fetch_and_merge(actor: current_user, discard_changes: discard_changes)
      flash[:notice] = result[:message]
    rescue Git::Ref::RejectedError
      return head :unprocessable_entity
    rescue Git::Ref::MergeConflictError
      flash[:error] = "There are merge conflicts"
    rescue Git::Ref::FetchAndMergeFailure => e
      flash[:error] = e.ui_message
    end

    redirect_to tree_url(name: params[:name])
  end

  # Gets the body of the dialog to use for branch deletion on /branches. Returns an empty string if the branch should
  # be deleted immediately with no confirmation.
  def delete_branch_dialog # rubocop:todo GitHub/UseRestfulActions
    branch_name = params[:name]

    if branch_name.blank? || !current_repository&.heads&.exist?(branch_name)
      head 404
      return
    end

    raw_open_pulls = PullRequest.find_open_based_on_ref(current_repository, branch_name)
    to_respond = ""

    if !raw_open_pulls.empty?
      open_pulls = raw_open_pulls.take(3).map do |pr|
        {
          title: pr.title,
          url: pr.url,
          number: pr.number
        }
      end

      to_respond = render_to_string(
        partial: "branches/delete_branch_dialog",
        formats: [:html],
        locals: {
          open_pulls: open_pulls,
          total: raw_open_pulls.length,
          branch: branch_name
        })
    end

    respond_to do |format|
      format.html { render html: to_respond }
    end
  end

  def check_tag_name_exists # rubocop:todo GitHub/UseRestfulActions
    branch_name = params[:value]
    if current_repository&.tags.exist?(branch_name)
      return render Branch::CreateErrorComponent.new(message: "A tag already exists with the provided branch name. Many Git commands accept both tag and branch names, so creating this branch may cause unexpected behavior. Are you sure you want to create this branch?"), layout: false
    end

    head :ok
  end

  private

  def route_supports_advisory_workspaces?
    true
  end

  def is_react_request?(request)
    return false unless request.format.json?
    return @react_repos_code_view if instance_variable_defined?(:@react_repos_code_view)
    @react_repos_code_view = code_view_enabled?
  end

  def current_layout
    if @rendering_react_view
      # We set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
      # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
      "layouts/repository_with_container"
    else
      "repository"
    end
  end

  sig { params(selected_view: Symbol, page: T.nilable(Integer), query: T.nilable(String)).void }
  def render_branches_page(selected_view, page = nil, query = nil)
    GitHub.dogstats.increment("repos-react-migration.react", tags: dogstats_request_tags)

    user = current_user || User.ghost

    @rendering_react_view = true

    render_react_app(
      app_payload_generator: -> {
        {
          repo: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          createBranchButtonOptions: {
            branchListCacheKey: ref_list_cache_key,
            repository: Repos::ReactPayload.current_repository_payload(current_repository, current_user_can_push: current_user_can_push?),
            repositoryParent: if T.must(current_repository).fork? && T.cast(T.must(current_repository).parent, T.nilable(Repository))&.readable_by?(current_user) # rubocop:todo GitHub/AvoidCast
                                Repos::ReactPayload.current_repository_payload(T.must(current_repository).parent, current_user_can_push: false)
                              else
                                nil
                              end,
            createUrl: create_branch_path,
            helpUrl: GitHub.help_url
          },
          currentUser: {
            login: user.display_login,
            name: user.name,
            avatarUrl: user.primary_avatar_url(80),
            path: user_path(user)
          },
          enabled_features: {
            branches_race_condition_fix: T.must(current_repository).feature_enabled?(:branches_race_condition_fix),
          },
        }
      },
      payload: case selected_view
               when :overview
                 branches_overview_payload
               else
                 branches_list_payload(selected_view, page, query)
               end,
      title: "Branches · #{T.must(current_repository).name_with_display_owner}",
      page_data: {
        selected_link: :repo_source,
      },
    )
  end
end
