# typed: true
# frozen_string_literal: true

class Api::Pulls < Api::App
  include ReceiveSchemaWithOpenApi

  include Api::App::DiffContentsDependency
  include Api::App::DatabaseConnectionHelper

  map_to_service :pull_requests # rubocop:todo GitHub/MapToService

  # List pull requests for this repository
  get "/repositories/:repository_id/pulls", operation_id: "pulls/list", resolve_tenant_context: :resolve_tenant_from_repo do
    with_replica_clusters([ApplicationRecord::Repositories]) do
      control_access :list_pull_requests, repo: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      indifferent_params = HashWithIndifferentAccess.new(params.merge(pagination))

      if repo&.feature_enabled?(:pulls_rest_status_filtering)
        RestApiStatusFilterExperimentJob.perform_later(repository_id: repo.id, user_id: current_user&.id, indifferent_params: indifferent_params.to_hash)
      end

      pulls = if repo.feature_enabled?(:pulls_issue_subquery_experiment) && should_use_issue_sort?(indifferent_params, repo)
        science "pull_requests.rest_api_issue_subquery" do |e|
          e.use { pull_requests_sorted_by_pull_requests_table(repo, indifferent_params) }
          e.try { pull_requests_sorted_by_issues_table(repo, indifferent_params) }
          e.compare_record_sequence
        end
      else
        pull_requests_sorted_by_pull_requests_table(repo, indifferent_params)
      end

      GitHub.dogstats.time "prefill", tags: ["via:api", "action:pulls_list"] do
        PullRequest.prefill_rest_api_list_repo_pulls(pulls, current_user, mirror: true)
        deliver :pull_request_hash, pulls, repo: repo
      end
    end
  end

  def pull_requests_sorted_by_pull_requests_table(repo, indifferent_params)
    pulls =
      if repo&.feature_enabled?(:only_filter_by_user_if_user_spammy)
        repo.pull_requests.filter_spam_for(current_user, skip_user_filter_if_not_spammy: true)
      else
        repo.pull_requests.filter_spam_for(current_user)
      end

    if head_label = params[:head]
      head_ref, head_owner = head_label.split(":").reverse
      if head_owner
        head_repo = Repositories.domain.networks.find_fork_in_network_for_user(repo, head_owner)
        pulls = pulls.for_head_repo_and_head_ref(head_repo, head_ref)
      end
    end

    if base_ref = params[:base]
      pulls = pulls.for_base_ref(base_ref).where("pull_requests.base_repository_id = pull_requests.repository_id")
    end

    pulls = paginate_rel(pulls.filtered_and_ordered(indifferent_params))

    state = indifferent_params[:state]
    should_rewrite_join = if repo.feature_enabled?(:pull_requests_api_count_index_hint_more_often)
      state != "all"
    else
      state.present? && state != "all"
    end

    if should_rewrite_join
      # This works around a performance problem, where the MySQL query optimiser
      # will select the unique `pull_request_id` index over a non-unique index
      # that covers all of the fields in the `WHERE` clause.
      # See: https://github.com/github/killed-query-dashboard-updater/issues/913
      counter_scope = pulls.unscope(:joins).joins(Arel.sql(<<-SQL))
        INNER JOIN `issues` IGNORE INDEX (`index_issues_on_pull_request_id_unique`)
        ON `issues`.`pull_request_id` = `pull_requests`.`id`
      SQL
      pulls.total_entries = counter_scope.total_entries
    end

    pulls
  end

  def pull_requests_sorted_by_issues_table(repo, indifferent_params)
    issue_sort_scope = build_issue_sort_scope(repo, indifferent_params)
    pr_ids = issue_sort_scope.pluck(:pull_request_id)
    # The IDs are already sorted from the issues table so order the pull request results by the order of the returned IDs
    pulls = repo.pull_requests.where(id: pr_ids).order(Arel.sql("field(pull_requests.id, #{pr_ids.join(',')})"))

    # Copy over pagination attributes
    pulls = pulls.extending(WillPaginate::ActiveRecord::RelationMethods)
    pulls = pulls.per_page(issue_sort_scope.per_page)
    pulls.current_page = issue_sort_scope.current_page
    pulls.total_entries = issue_sort_scope.total_entries

    pulls
  end

  USE_ISSUE_SORT_LIMIT = 20_000
  def should_use_issue_sort?(params, repo)
    return false if (params.keys.map(&:to_s) & %w[head base]).any?
    return false if %w[long-running longevity].include?(params[:sort])

    return true if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    GitHub.dogstats.time("pull_requests.api.issue_count_query") do
      return false unless repo.issues.limit(USE_ISSUE_SORT_LIMIT + 1).count > USE_ISSUE_SORT_LIMIT
    end
    true
  end

  def sort_and_direction(params)
    if (sort = params[:sort]).blank?
      sort = "created"
      direction = params[:direction] || "desc"
    end
    direction ||= params[:direction] || "asc"

    sort = "comments" if sort == "popularity"
    [sort, direction.downcase].join("-")
  end

  def build_issue_sort_scope(repo, params)
    search_components = []
    search_components << [:is, "pr"]
    search_components << [:sort, sort_and_direction(params)]
    state =
      case params[:state]
      when /close/
        "closed"
      when "all"
        nil
      else
        "open"
      end
    search_components << [:is, state] if state.present?

    show_spam_to_staff = current_user&.show_spammy_issues_to_staff_enabled?
    if Issue::MysqlSearch.repo_spammy_for?(repo, current_user, show_spam_to_staff)
      # Use a NullRelation, effectively hiding issues coming from a spammy repo.
      scope = repo.issues.none
    else
      scope = Issue::MysqlSearch.partial_query_scope(
        repo: repo,
        current_user: current_user,
        query: search_components,
        force_type: :pull_requests,
        show_spam_to_staff: show_spam_to_staff,
      )
    end

    _, scope = Issue::MysqlSearch.state_scope(search_components, scope)
    # get count before sorting
    pagination[:total_entries] = scope.count

    sort = Issue::MysqlSearch.get_sort(search_components)
    scope = Issue::MysqlSearch.sort_scope(sort, scope)

    if scope.null_relation?
      scope.paginate(pagination)
    else
      pagination_scope = scope.select(:id).paginate(pagination)
      scope = Issue::MysqlSearch.sort_scope(sort, Issue.where("`issues`.`id` IN (SELECT * FROM (?) subquery_for_limit)", pagination_scope))

      # Copy over pagination attributes
      scope = scope.extending(WillPaginate::ActiveRecord::RelationMethods)
      scope = scope.per_page(per_page)
      scope.current_page = pagination_scope.current_page
      scope.total_entries = pagination_scope.total_entries
      scope
    end
  end

  # Create a pull request
  post "/repositories/:repository_id/pulls", operation_id: "pulls/create" do
    control_access :create_pull_request,
      repo: repo = find_repo!,
      enforce_oauth_app_policy: current_repo.private?,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    authorize_content(:create, repo: repo)

    # TODO: replace `legacy-create-legacy` with `create`
    # Introducing strict validation of the pull-request.create
    # JSON schema would cause breaking changes for integrators
    # Use pull-request.legacy-create-legacy until a rollout strategy
    # can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("pull-request", "legacy-create-legacy")

    attributes = attr(data, :title, :body, :base, :head, :head_repo, :maintainer_can_modify, :draft).
      update("user" => current_user)

    if attributes["draft"]
      # Gather metrics for values submitted for the draft parameter, as
      # a precursor for enforcing that the submitted data type be boolean.
      draft_value_type = :other
      case attributes["draft"]
      when TrueClass, FalseClass
        draft_value_type = :boolean
      when String
        if %w(true false).include?(attributes["draft"])
          draft_value_type = :string
        end
      end
      GitHub.dogstats.increment("api_create_pull.draft_param", tags: ["type:#{draft_value_type}"], sample_rate: 0.1)
    end

    if attributes["draft"] && !repo.plan_supports?(:draft_prs)
      deliver_error! 422,
        message: "Draft pull requests are not supported in this repository."
    end

    # TODO Move this validation to the JSON schema, once it can provide a better
    # error message. (http://git.io/J6aVVA)
    # Note: A patch was submitted to improve the error message (https://github.com/brandur/json_schema/pull/26),
    # but it's still not clear enough for our purposes.
    if data.key?("issue") && data.key?("title")
      deliver_error! 422,
        message: "You may only provide an issue number or a title string, but not both."
    end

    if (num = data["issue"].to_i) > 0
      log_data.update(alternative_input: true)

      if issue = repo.issues.find_by_number(num)

        # disallow converting to pull request when sub-issues or parent relationship is present
        if issue.parent&.present? || issue.sub_issues&.present?
          deliver_error! 422,
          errors: [api_error(:PullRequest, :issue, :invalid)],
          message: "Cannot convert an issue with a parent or sub-issue relationship to a pull request."
        end

        # disallow removing existing issue -> pull request relationship.
        if issue.pull_request?
          deliver_error! 422,
            errors: [api_error(:PullRequest, :issue, :invalid, value: num)],
            message: "The specified issue is already attached to a pull request."
        end

        has_access = access_allowed? :edit_issue,
           resource: issue,
           user: current_user, # rubocop:disable GitHub/DisallowEgressUserKey
           repo: repo,
           allow_integrations: true,
           allow_user_via_granular_actor: true

        if !has_access
          deliver_error! 422,
            errors: [api_error(:PullRequest, :issue, :unauthorized, value: num)],
            message: "You do not have permission to attach the specified issue."
        end

        attributes[:issue] = issue
      else
        deliver_error! 422,
          errors: [api_error(:PullRequest, :issue, :invalid, value: num)],
          message: "The specified issue does not exist."
      end
    end

    if attributes[:base].blank?
      deliver_error! 422,
      errors: [api_error(:PullRequest, :base, :missing_field)]
    end

    if attributes[:base].to_s.include?(":")
      deliver_error! 422,
        errors: [api_error(:PullRequest, :base, :invalid)]
    end

    if attributes[:maintainer_can_modify] == false
      attributes[:collab_privs] = attributes.delete(:maintainer_can_modify)
    else
      attributes[:maintainer_can_modify] = true
    end

    head = attributes[:head].b.sub(%r{refs/heads/}, "")
    base = attributes[:base].b.sub(%r{refs/heads/}, "")

    if attributes[:head_repo].present?
      attributes[:comparison] = repo.comparison(
        base,
        head,
        head_repo: Repositories.domain.by_qualified_name(attributes[:head_repo])
      )
    else
      attributes[:comparison] = repo.comparison(
      base,
      head
      )
    end

    if attributes[:maintainer_can_modify] && disallow_fork_collab_access?(head_repository: attributes[:comparison].head_repo, base_repository: attributes[:comparison].base_repo, actor: current_user)
      GitHub.logger.info("fork_collab access granted without head repo permissions", "gh.request_id": GitHub.context[:request_id])

      attributes[:maintainer_can_modify] = false
    end

    # TODO: Remove this special-case header, see: https://github.com/github/dependabot-api/issues/526
    if current_integration&.dependabot_github_app?
      attributes[:dependabot_update_id] = request.env["HTTP_X_DELTAFORCE_DEPENDENCY_UPDATE_ID"]
    end

    begin
      pull = PullRequest.create_for(repo, attributes)
    rescue ActiveRecord::RecordInvalid => e
      deliver_error! 422,
        errors: e.record.errors
    end

    pull = T.must(pull)

    if pull.persisted?
      if !T.must(pull.head_repository).heads.read(pull.head_ref).exist?
        log_data[:pull_request_non_branch_head] = pull.head
        err = PullRequest::NonBranchHeadError.new(pull.head)
        err.set_backtrace(caller)
        Failbot.report_user_error(err, "gh.pull_request.fatal": "NO (just reporting)", "gh.pull_request.head_repo.id": pull.head_repository_id)
      end

      pull.enqueue_mergeable_update

      PullRequest.prefill_associations([pull])
      deliver :pull_request_hash, pull, { full: true, status: 201 }
    else
      branch_errors = []
      if pull.errors[:base_ref].any?
        branch_errors << api_error(:PullRequest, :base, :invalid)
      end
      if pull.errors[:head_ref].any?
        branch_errors << api_error(:PullRequest, :head, :invalid)
      end

      deliver_error 422,
        errors: branch_errors.any? ? branch_errors : pull.errors
    end
  end

  GIT_SUMMARY_TIMEOUT_SECS = 2
  GIT_CONTENTS_TIMEOUT_SECS = 6
  # Get a single pull request
  get "/repositories/:repository_id/pulls/:pull_number", operation_id: "pulls/get" do
    repo, pull = find_repo_and_pull_request

    if medias.api_param?(:diff)
      control_access :get_contents,
        resource: repo,
        path: nil,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :get_pull_request,
        repo: repo,
        resource: pull,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    PullRequest.prefill_associations([pull], mirror: true)

    if medias.api_param?(:diff) || medias.api_param?(:patch)
      delivering_raw_diff_content(medias) do
        pull.set_diff_options(timeout: GIT_CONTENTS_TIMEOUT_SECS) if pull.repository&.feature_enabled?(:pull_api_diff_timeout)
        comparison = pull.historical_comparison
        diff = comparison.diffs

        if !diff.available? || diff.truncated_for_timeout? || diff.truncated_for_max_lines? || diff.truncated_for_max_files?
          deliver_undiffable_error!(:PullRequest, comparison.diffs)
        end

        raw_comparison = if medias.api_param?(:diff)
          comparison.to_diff
        else
          comparison.to_patch
        end

        deliver_raw raw_comparison,
          content_type: "#{medias}; charset=utf-8",
          last_modified: calc_last_modified_for_object(pull)
      end
    else
      begin
        pull.set_diff_options(timeout: GIT_SUMMARY_TIMEOUT_SECS) if pull.repository&.feature_enabled?(:pull_api_diff_timeout)
        # we calculate a new merge commit, if necessary, on read.
        # this is done asynchronously so the current request is not held up
        # but so that there is a chance future requests will have
        # knowledge of the pull's mergeability.
        pull.enqueue_mergeable_update

        deliver :pull_request_hash, pull, {
          full: true,
          repo: repo,
          last_modified: calc_last_modified_for_object(pull),
          current_user: current_user,
        }
      # TODO: This rescue block is here to gather telemetry on the impact of removing
      # `delivering_raw_diff_content` from the above block. It should be removed once
      # we have enough data to determine the impact and any errors that could be handled
      # by the above block are handled.
      #
      # TIMEBOX: This block should be removed be March 2024
      rescue GitRPC::ObjectMissing, GitRPC::InvalidObject => e
        Failbot.report_trace(e)
        deliver_error! 404
      rescue GitRPC::Timeout => e
        Failbot.report_trace(e)
        deliver_error! 422, message: "The request could not be processed because too many files changed"
      end
    end
  end

  # Update a pull request
  verbs :patch, :post, "/repositories/:repository_id/pulls/:pull_number", operation_id: "pulls/update", resolve_tenant_context: :resolve_tenant_from_repo do
    with_replica_clusters([ApplicationRecord::Repositories], current_user: current_user) do
      repo, pull = find_repo_and_pull_request
      control_access :update_pull_request,
        repo: repo,
        resource: pull,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?
      authorize_content(:update, repo: repo)

      # Introducing strict validation of the pull-request.update
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      data = receive_with_schema("pull-request", "update", skip_validation: true, expected_type: Hash)

      # Assert that only the pull author may change the fork collaboration grant setting.
      if data.key?("maintainer_can_modify") && current_user != pull.user
        deliver_error! 422,
          resource: "PullRequest",
          errors: [
            api_error(:PullRequest, :maintainer_can_modify, :invalid,
              message: "Only the pull request author may change the maintainer_can_modify value"),
          ]
      end

      attributes = attr(data, :title)
      issue = T.must(pull.issue)
      # disable update issue orchestration call back on updates, we will invoke this manually after all changes are made
      # to the issue
      issue.skip_update_issue_orchestration = true
      # opt into hydro instrumentation in the orchestration job rather than synchronously during the request
      issue.orchestrate_hydro_update_event_instrumentation = true

      issue_previous_title = issue.title

      saved = if data["state"].to_s =~ /\Aclose/i && issue.open?
        issue.close(current_user, attributes: attributes)
      elsif data["state"].to_s =~ /\Aopen/i && issue.closed?
        issue.open(current_user, attributes)
      else
        issue.update(attributes)
      end

      if data.key?("body")
        issue.update_body(data["body"], current_user)
      end

      if data.key?("maintainer_can_modify") && disallow_fork_collab_access?(actor: current_user, head_repository: pull.head_repository, base_repository: pull.base_repository)
        data["maintainer_can_modify"] = false
      end

      if data.key?("maintainer_can_modify")
        pull.fork_collab_state = data["maintainer_can_modify"] ? :allowed : :denied
        saved = pull.save if pull.changed?
      end

      if data.key?("base")
        begin
          pull.change_base_branch(current_user, data["base"])
        rescue ArgumentError => e
          deliver_error! 422,
            resource: "PullRequest",
            errors: [
              api_error(:PullRequest, :base, :invalid,
                message: e.message),
            ]
        rescue PullRequest::BaseNotChangeableError => e
          deliver_error! 422,
            resource: "PullRequest",
            errors: [
              api_error(:PullRequest, :base, :invalid,
                message: e.ui_message),
            ]
        rescue Git::Ref::NotFound
          deliver_error! 422,
            resource: "PullRequest",
            errors: [
              api_error(:PullRequest, :base, :invalid,
                message: "Proposed base branch '#{data["base"]}' was not found"),
            ]
        end
      end

      if saved
        update_issue_orchestration = IssueOrchestration.update_issue!(actor: current_user, issue: issue)
        if issue.title != issue_previous_title
          # manually add the title changes to the job payload bc in cases where both title and body are updated in a
          # single request, it will only see the latest (body) issue edit
          update_issue_orchestration.data.deep_merge!({
            title_or_body_changes: {
              old_title: issue_previous_title,
              current_title: issue.title,
            }
          })
        end
        update_issue_orchestration.execute!

        pull.enqueue_mergeable_update

        PullRequest.prefill_associations([pull], mirror: true)

        deliver :pull_request_hash, pull, {
          full: true,
          repo: repo,
          current_user: current_user,
        }
      else
        errors = pull.errors.any? ? pull.errors : issue.errors
        deliver_error 422,
          resource: "PullRequest",
          errors: errors
      end
    end
  end

  # Check if a pull request is merged
  get "/repositories/:repository_id/pulls/:pull_number/merge", operation_id: "pulls/check-if-merged" do
    repo, pull = find_repo_and_pull_request
    control_access :get_pull_request_merge_status,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if pull.merged?
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  # Merge a pull request
  put "/repositories/:repository_id/pulls/:pull_number/merge", operation_id: "pulls/merge" do
    repo, pull = find_repo_and_pull_request

    control_access(:merge_pull_request,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    )
    authorize_content(:merge, repo: repo)
    ensure_repo_writable!(repo)

    ref_update_policy = nil

    if repo.feature_enabled?(:pulls_api_merge_workflow_detailed_error)
      ref_update_policy = RefUpdates::WorkflowUpdatesPolicy.new(current_user, repo).check_ref_update(pull.current_base_sha, pull.head_sha)
      set_forbidden_message ref_update_policy.short_message unless ref_update_policy.allowed?
    end

    control_access :update_ref_v2,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      repo: repo,
      before_oid: pull.current_base_sha,
      after_oid: pull.head_sha,
      ref_update_policy: ref_update_policy

    data = receive_with_schema("pull-request", "merge-legacy")
    sha_param!("sha", data) if data.key?("sha")

    begin
      # login not used in respose therefore safe to use here.
      reflog_data = request_reflog_data("pull request merge api").merge({ pr_author_login: pull.safe_user.login }) # rubocop:disable GitHub/DoNotAllowLogin
      method = data["merge_method"].try(:to_sym) || :merge

      case result = PullRequests::Merge.call(
        pull_request: pull,
        user: current_user,
        method:,
        reflog_data:,
        commit_body: data["commit_message"],
        commit_title: data["commit_title"],
        expected_head_sha: data["sha"],
      )
      when PullRequests::Merge::Success
        deliver_raw(
          sha: result.sha,
          merged: true,
          message: "Pull Request successfully merged")
      when PullRequests::Merge::Failure
        error_code = 405
        error_code = 409 if result.code == :head_mismatch
        error_code = 403 if result.code == :workflow_policy_update_error

        response = {
          sha: nil,
          merged: false,
          message: result.error_message,
        }

        if result.code == :protected_branch
          response[:documentation_url] = "#{GitHub.help_url}/articles/about-protected-branches"
        end

        deliver_error error_code, response
      else
        T.absurd(result)
      end
    rescue Git::Ref::HookFailed => e
      deliver_error 422,
        message: "Could not merge because a Git pre-receive hook failed.\n\n#{e.message}",
        documentation_url: "#{GitHub.help_url}/articles/about-protected-branches"
    end
  end

  # Merge HEAD from upstream branch into pull request branch
  put "/repositories/:repository_id/pulls/:pull_number/update-branch", operation_id: "pulls/update-branch" do
    repo, pull = find_repo_and_pull_request

    control_access(:update_pull_request,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    authorize_content(:update, repo: repo)
    ensure_repo_writable!(repo)

    data = receive_with_schema("pull-request", "update-branch")

    params = {
      user: current_user,
      author_email: current_user&.default_author_email(pull.repository, pull.head_sha),
    }

    params[:expected_head_oid] = data["expected_head_sha"] if data["expected_head_sha"]

    begin
      # Check if the API call authorized by an integration, and if this integration is having write access to repo contents
      # Notes:
      # - This is a temp. fix to remedy https://github.com/github/coding/issues/2358
      # - We have https://github.com/github/coding/issues/2435 to resolve the core issue at `Repository::OrganizationsDependency#pushable_by?`
      # TODO: Remove this block once https://github.com/github/coding/issues/2435 is fixed
      unless PullRequest::RepoWriteAccessViaIntegrationAuthorizer.new(repo: pull.head_repository, actor: current_user).allow?
        GitHub.logger.info(
          "attempt to call the update-branch API without permission on head repo contents",
          "gh.request_id" => GitHub.context[:request_id]
        )

        raise PullRequest::PermissionError, "user doesn't have permission to update head repository"
      end

      if data["update_method"] == "rebase"
        pull.rebase_head_on_base(**params)
      else
        pull.merge_base_into_head(**params)
      end
    rescue PullRequest::MergeConflictError => e
      deliver_error!(422, message: e.message)
    rescue PullRequest::RebaseConflictError => e
      deliver_error!(422, message: e.message)
    rescue PullRequest::RefMismatch, Git::Ref::ComparisonMismatch
      deliver_error!(422, message: "expected head sha didn’t match current head ref.")
    rescue PullRequest::HeadMissing => e
      deliver_error!(422, message: e.message)
    rescue PullRequest::PermissionError => e
      deliver_error!(403, message: e.message)
    rescue Git::Ref::ProtectedBranchUpdateError => e
      deliver_error!(422, message: e.message)
    rescue Git::Ref::RepositoryRuleViolationError => e
      deliver_error!(422, message: e.detailed_message)
    rescue Git::Ref::WorkflowUpdatePolicyError => e
      deliver_error!(403, message: e.message)
    rescue GitHub::UIError => e
      deliver_error!(422, message: e.ui_message)
    end

    url = api_url("/repos/#{repo.name_with_display_owner}/pulls/#{pull.number}")
    message = "Updating pull request branch."
    response["location"] = url
    deliver_raw({ message: message, url: url }, status: 202)
  end

  # List pull request commits
  get "/repositories/:repository_id/pulls/:pull_number/commits", operation_id: "pulls/list-commits" do
    repo, pull = find_repo_and_pull_request
    control_access :list_pull_request_commits,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    opts = { repo: repo, global_id_selection: global_id_selection, map_items: false }
    opts.update(pagination)

    if (mimes = request.accept).present?
      opts[:accept_mime_types] = mimes
    end

    deliver_raw Api::Serializer.serialize(:commits_array, pull.changed_commits, opts),
      last_modified: calc_last_modified_for_object(pull)
  end

  # List pull request files (diffs)
  get "/repositories/:repository_id/pulls/:pull_number/files", operation_id: "pulls/list-files" do
    repo, pull = find_repo_and_pull_request
    control_access :list_pull_request_files,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    diff = pull.historical_comparison.init_diffs

    delta_index_from = pagination[:per_page] * (pagination[:page] - 1) # Subtract 1 page num since it's 1-indexed
    delta_index_to = (pagination[:per_page] * pagination[:page]) - 1   # Subtract 1 from product since delta_indexes are inclusive. We want 0..29, not 0..30.
    diff.add_delta_indexes((delta_index_from..delta_index_to).to_a)

    if !diff.available? || diff.truncated_for_timeout?
      deliver_undiffable_error!(:PullRequest, diff)
    end

    files = diff.to_a

    paginator.collection_size = pull.diffs.changed_files

    deliver :condensed_diff_entry_hash, files,
      repo: repo,
      last_modified: calc_last_modified_for_object(pull)
  end

  def resolve_tenant_from_repo
    repo = find_repo!
    Business.find_by(id: repo.tenant_id)
  end

  private

  sig { returns([Repository, PullRequest]) }
  def find_repo_and_pull_request
    repo = T.let(find_repo!, Repository)
    pull_accessor = PullRequests::PullRequestAccessor.new

    pull = begin
      pull_accessor.by_number(repository_id: T.must(repo.id), number: int_id_param!(key: :pull_number))
    rescue GH::Errors::ObjectNotFound
      deliver_error!(404)
    end

    pull = T.cast(pull, PullRequest)

    # TODO: move this check into the domain interface and return possibly a ViewerUnauthorized Problem?
    deliver_error!(404) if pull.hide_from_user?(current_user)

    [repo, pull]
  end

  def authorize_content(operation = :create, data = {})
    authorization = ContentAuthorizer.authorize(current_user, :pull_request, operation, data)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

  def disallow_fork_collab_access?(actor:, head_repository:, base_repository:)
    PullRequest::ForkCollabAccessViaIntegrationAuthorizer.new(actor: actor,
      head_repository: head_repository,
      base_repository: base_repository).disallow?
  end
end
