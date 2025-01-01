# typed: true
# frozen_string_literal: true

module RefUpdates
  class WorkflowUpdatesPolicy
    attr_reader :actor, :repository

    # We do not want to allow these files to be overwritten / writable from GitHub
    # Apps that are being used in Actions.
    WORKFLOW_DIRS = %w(.github/workflows/ .github/workflows-lab/)

    class FileUpdate
      attr_reader :path, :oid

      def initialize(path, oid)
        @path = path
        @oid = oid
      end

      def workflow_file?
        return false unless path.is_a?(String)
        WORKFLOW_DIRS.any? do |unwritable|
          path.start_with? unwritable
        end
      end

      def deletion?
        oid == GitHub::NULL_OID
      end
    end

    def initialize(actor, repository)
      @actor = actor
      @repository = repository
    end

    def check_file_update(path, oid, timeout: 3)
      unless workflow_scope_missing?
        return RefUpdatesPolicy::Decision.new(true, nil)
      end

      update = FileUpdate.new(path, oid)

      unless update.workflow_file?
        return RefUpdatesPolicy::Decision.new(true, nil)
      end

      timer = Timer.start
      result = check_workflow_file_updates([update], timeout: timeout)

      timer.stop
      GitHub.dogstats.distribution("actions.workflow_scope.timing.workflow_updates_policy_check_file_update", timer.elapsed_ms)
      GitHub.logger.info(
        "code.namespace" => "RefUpdates::WorkflowUpdatePolicy",
        "code.function" => "check_file_update",
        "gh.repo.name_with_owner" => repository.nwo)

      result
    rescue GitRPC::Timeout
      GitHub.dogstats.increment("actions.workflow_scope.gitrpc_timeouts")
      raise
    end

    def check_files_update(files, timeout: 3)
      unless workflow_scope_missing?
        return RefUpdatesPolicy::Decision.new(true, nil)
      end

      workflow_files = files.filter { |file| file.workflow_file? }
      if workflow_files.empty?
        return RefUpdatesPolicy::Decision.new(true, nil)
      end

      timer = Timer.start
      result = check_workflow_file_updates(workflow_files, timeout: timeout)

      timer.stop
      GitHub.dogstats.distribution("actions.workflow_scope.timing.workflow_updates_policy_check_files_update", timer.elapsed_ms)
      GitHub.logger.info(
        "code.namespace" => "RefUpdates::WorkflowUpdatePolicy",
        "code.function" => "check_files_update",
        "gh.repo.name_with_owner" => repository.nwo)

      result
    rescue GitRPC::Timeout
      GitHub.dogstats.increment("actions.workflow_scope.gitrpc_timeouts")
      raise
    end

    def check_ref_update(before_oid, after_oid, timeout: 3)
      # These code implements a prohibition on apps pushing code to workflow
      # files using "git push". There's a similar set of logic in
      # config/access_control/roles.rb definition of :repo_file_writer that
      # governs writing workflows/a.yml using the API.
      # If you make changes here, consider updating that one, too.
      unless workflow_scope_missing?
        return RefUpdatesPolicy::Decision.new(true, nil)
      end
      # Refs can point to any git object but Actions can only execute on treeish
      # objects, as there is no concept of a workflow file within them otherwise.
      #
      # Peel the git object to retrieve a commit, tree or nil. We could peel to
      # trees but using commits where possible will reduce the size of the cache
      # for `read_tree_diff` as all other callers use commits.
      #
      # We can use NULL_OID instead of non-treeish objects to produce diffs.
      # e.g.
      #   ref is update from a blob to a commit
      #   diff null_oid and commit to check if a new workflow file will be added
      safe_peel_to_commit = ->(commitish) {
        oid = begin
            repository.rpc.peel_to_commit_or_tree(commitish)
          rescue GitRPC::ObjectMissing, # peel or find
                 GitRPC::Failure,       # peel recursion depth limit reached, malformed oid
                 GitRPC::InvalidObject, # peel resolves to tree
                 TypeError              # peel did not resolve for some other reason.
          end
        oid || GitHub::NULL_OID # if we cannot find the commit, assume it is a full branch creation or deletion
      }

      timer = Timer.start
      peeled_before_oid = safe_peel_to_commit.call(before_oid)
      peeled_after_oid = safe_peel_to_commit.call(after_oid)
      diff = repository.rpc.read_tree_diff(peeled_before_oid, peeled_after_oid, paths: WORKFLOW_DIRS, diff_trees: true)
      workflow_files_updated = diff.filter_map do |diff_entry|
        file = diff_entry["new_file"]
        update = FileUpdate.new(file["path"], file["oid"])
        # When considering diffs nil and GitHub::NULL_OID are considered the same.
        # This is different to how WorkflowUpdatesPolicy#check_file_update
        # handles nils.
        update if update.workflow_file? && update.oid.present?
      end

      result = check_workflow_file_updates(workflow_files_updated, timeout: timeout)

      timer.stop
      GitHub.dogstats.distribution("actions.workflow_scope.timing.workflow_updates_policy_check", timer.elapsed_ms)
      GitHub.logger.info(
        "code.namespace" => "RefUpdates::WorkflowUpdatePolicy",
        "code.function" => "check_ref_update",
        "gh.repo.name_with_owner" => repository.nwo,
        "gh.repo.branch_count" => repository.heads.size,
        "gh.actions.workflow_files.update_count" => workflow_files_updated.size,
        "gh.actions.ref_update.before_oid" => before_oid,
        "gh.actions.ref_update.after_oid" => after_oid,
      )

      result
    rescue GitRPC::Timeout
      GitHub.dogstats.increment("actions.workflow_scope.gitrpc_timeouts")
      raise
    end

    def check_ref_updates(ref_updates, timeout: 3)
      timer = Timer.start
      ref_updates.each do |ref_update|
        timeout -= (timer.elapsed_ms / 1000)
        raise GitRPC::Timeout if timeout <= 0
        decision = check_ref_update(ref_update.before_oid || GitHub::NULL_OID, ref_update.after_oid, timeout: timeout)
        return decision unless decision.allowed?
      end
      RefUpdatesPolicy::Decision.new(true, nil)
    end

    def workflow_scope_missing?
      auth_via_integration_without_workflow_permission ||
        auth_via_pat_without_workflow_scope ||
        auth_via_oauth_app_without_workflow_scope ||
        auth_via_programmatic_access_without_workflow_permission ||
        public_key_from_oauth_without_workflow_write_scope ||
        public_key_created_by_unknown
    end

    private

    def check_workflow_file_updates(workflow_files, timeout:)
      workflow_files = workflow_files.reject(&:deletion?)
      return RefUpdatesPolicy::Decision.new(true, nil) if workflow_files.empty?

      timer = Timer.start
      # If there is a default branch, check for the existance of the workflow file there first and short-circuit
      branches = repository.refs.select(&:branch?)
      begin
        workflow_files = files_missing_from_branches(workflow_files, branches.select(&:default_branch?), timeout: 1)
      rescue GitRPC::Timeout
        GitHub.dogstats.increment("actions.workflow_scope.gitrpc_timeouts.default_branch_check")
        GitHub.dogstats.distribution("actions.workflow_scope.gitrpc_timeouts.default_branch_check.workflow_file_update_count", workflow_files.count)
        GitHub.logger.info(
          "Timed out while checking if workflow scope is required - default branch",
          "code.namespace" => "RefUpdates::WorkflowUpdatePolicy",
          "code.function" => "check_workflow_file_updates",
          "gh.repo.branch_count" => branches.size,
          "gh.actions.workflow_files.update_count" => workflow_files.size,
          "gh.repo.name_with_owner" => repository.nwo,
          "gh.oauth.application.id" => oauth_app&.id,
          "gh.oauth.application.name" => oauth_app&.name,
          "gh.oauth.application.owner" => oauth_app&.user&.login,
          "gh.app.id" => github_app&.id,
          "gh.app.name" => github_app&.name,
          "gh.app.owner" => github_app_display_owner_login,
          "gh.actions.auth_via_pat_without_workflow_scope" => auth_via_pat_without_workflow_scope,
          "gh.actions.public_key_created_by_unknown" => public_key_created_by_unknown,
        )
        raise GitRPC::Timeout, "Timed out while checking if workflow scope is required - default branch check"
      end
      if workflow_files.empty?
        GitHub.dogstats.increment("actions.workflow_scope.path_updateable_for_app", tags: ["workflow_exists_on_default_branch:true", "check_default_branch_first:true"])
        timer.stop
        GitHub.dogstats.distribution("actions.workflow_scope.timing.path_updateable_for_app", timer.elapsed_ms, tags: ["workflow_exists_on_default_branch:true", "check_default_branch_first:true"])
        GitHub.logger.info(
          "code.namespace" => "RefUpdates::WorkflowUpdatePolicy",
          "code.function" => "path_updateable_for_app",
          "gh.actions.workflow_exists_on_default_branch" => true,
          "gh.repo.name_with_owner" => repository.nwo,
        )
        return RefUpdatesPolicy::Decision.new(true, nil)
      end
      # For files that don't exist on the default branch check the the rest of the branches
      begin
        workflow_files = files_missing_from_branches(workflow_files, branches.reject(&:default_branch?), timeout: timeout)
      rescue GitRPC::Timeout
        other_branch_count = branches.count { |branch| !branch.default_branch? }
        workflow_file_update_count = workflow_files.size
        map_size = other_branch_count * workflow_file_update_count
        GitHub.dogstats.increment("actions.workflow_scope.gitrpc_timeouts.other_branches_check")
        GitHub.dogstats.distribution("actions.workflow_scope.gitrpc_timeouts.other_branches_check.other_branch_count", other_branch_count)
        GitHub.dogstats.distribution("actions.workflow_scope.gitrpc_timeouts.other_branches_check.workflow_file_update_count", workflow_file_update_count)
        GitHub.dogstats.distribution("actions.workflow_scope.gitrpc_timeouts.other_branches_check.map_size", map_size)
        GitHub.logger.info(
          "Timed out while checking if workflow scope is required - all branches",
          "code.namespace" => "RefUpdates::WorkflowUpdatePolicy",
          "code.function" => "check_workflow_file_updates",
          "gh.actions.workflow_exists_on_default_branch" => false,
          "gh.repo.branch_count" => other_branch_count,
          "gh.actions.workflow_files.update_count" => workflow_file_update_count,
          "gh.repo.name_with_owner" => repository.nwo,
          "gh.oauth.application.id" => oauth_app&.id,
          "gh.oauth.application.name" => oauth_app&.name,
          "gh.oauth.application.owner" => oauth_app&.user&.login,
          "gh.app.id" => github_app&.id,
          "gh.app.name" => github_app&.name,
          "gh.app.owner" => github_app_display_owner_login,
          "gh.actions.auth_via_pat_without_workflow_scope" => auth_via_pat_without_workflow_scope,
          "gh.actions.public_key_created_by_unknown" => public_key_created_by_unknown,
        )
        if repository.feature_enabled?(:fail_workflow_file_updates_on_timeout)
          # Report but don't raise
          Failbot.report!(GitRPC::Timeout.new("Timed out while checking if workflow scope is required - all branches check (denied create/update)"))
          return RefUpdatesPolicy::Decision.new(false, nil, "Unable to determine if workflow can be created or updated due to timeout; `workflows` scope may be required.")
        else
          raise GitRPC::Timeout, "Timed out while checking if workflow scope is required - all branches check"
        end
      end

      if workflow_files.empty?
        GitHub.dogstats.increment("actions.workflow_scope.path_updateable_for_app", tags: ["workflow_exists_on_default_branch:false", "check_default_branch_first:true"])
      end

      timer.stop
      GitHub.logger.info(
        "code.namespace" => "RefUpdates::WorkflowUpdatePolicy",
        "code.function" => "check_workflow_file_updates",
        "gh.actions.workflow_exists_on_default_branch" => false,
        "gh.actions.workflow_exists_on_other_branch" => workflow_files.empty?,
        "gh.repo.name_with_owner" => repository.nwo,
        "gh.oauth.application.id" => oauth_app&.id,
        "gh.oauth.application.name" => oauth_app&.name,
        "gh.oauth.application.owner" => oauth_app&.user&.login,
        "gh.app.id" => github_app&.id,
        "gh.app.name" => github_app&.name,
        "gh.app.owner" => github_app_display_owner_login,
        "gh.actions.auth_via_pat_without_workflow_scope" => auth_via_pat_without_workflow_scope,
        "gh.actions.public_key_created_by_unknown" => public_key_created_by_unknown,
      )
      GitHub.dogstats.distribution("actions.workflow_scope.timing.path_updateable_for_app", timer.elapsed_ms, tags: ["workflow_exists_on_default_branch:false", "check_default_branch_first:true"])

      failing_update = workflow_files.first
      return RefUpdatesPolicy::Decision.new(false, nil, bot_action_prohibited_message(failing_update.path)) if failing_update

      RefUpdatesPolicy::Decision.new(true, nil)
    end

    def files_missing_from_branches(files, branches, timeout:)
      return files if branches.empty?

      # `read_blob_oids` takes an array of tuples `[[sha, path], ...]`
      # It returns an array (`[oid, ...]`of the blob oids at the path/sha specified by each tuples
      #
      # 1. Create tuples for every combination of workflow file path and branch sha
      branch_path_tuples = files.product(branches).map { |f, b| [b.sha, f.path] }

      # 2. Get the list of oids
      # 3. We know that there `branch.size` number of oids per workflow file path, so group them together into Sets
      result_oids = repository.rpc.with_timeout(timeout) do
        repository.rpc.read_blob_oids(branch_path_tuples, skip_bad: true)
      end.each_slice(branches.size).map(&:to_set)

      # 4. For each workflow file check if one of the branches has the same oid at the same paths an update.
      files.reject.with_index do |f, i|
        result_oids[i].include?(f.oid)
      end
    end

    def github_app
      return unless auth_via_integration_without_workflow_permission
      installation_for_actor.try(:integration) # this isn't guaranteed to be a thing for programmatic access
    end

    sig { returns(T.nilable(String)) }
    def github_app_display_owner_login
      return nil unless github_app

      github_app.display_owner&.display_login
    end

    def oauth_app
      return unless auth_via_oauth_app_without_workflow_scope || public_key_from_oauth_without_workflow_write_scope
      actor.oauth_application
    end

    def bot_action_prohibited_message(path)
      # Clients might be depending upon these error messages. Before changing please check with:
      # * GitHub Desktop
      if auth_via_integration_without_workflow_permission
        "refusing to allow a GitHub App to create or update workflow `#{path}` without `workflows` permission"
      elsif auth_via_pat_without_workflow_scope || auth_via_programmatic_access_without_workflow_permission
        "refusing to allow a Personal Access Token to create or update workflow `#{path}` without `workflow` scope"
      elsif auth_via_oauth_app_without_workflow_scope || public_key_from_oauth_without_workflow_write_scope
        "refusing to allow an OAuth App to create or update workflow `#{path}` without `workflow` scope"
      else
        "refusing to allow an integration to create or update workflow `#{path}`"
      end
    end

    def auth_via_integration_without_workflow_permission
      installation = installation_for_actor
      return false unless installation
      !repository.resources.workflows.writable_by?(installation)
    end

    def installation_for_actor
      return unless actor.is_a?(User)
      return actor.ability_delegate if actor.bot?
      return unless actor.using_auth_via_integration?

      scoped_installation = actor.oauth_access.installation
      return scoped_installation if scoped_installation

      IntegrationInstallation.with_repository(repository).where(integration: actor.oauth_access.application).first
    end

    def auth_via_pat_without_workflow_scope
      actor.is_a?(User) && actor.using_personal_access_token? && !actor.oauth_access?("workflow")
    end

    def auth_via_oauth_app_without_workflow_scope
      actor.is_a?(User) && actor.using_auth_via_oauth_application? && !actor.oauth_access?("workflow")
    end

    def auth_via_programmatic_access_without_workflow_permission
      # Should we even get this far for gists? Feels like this policy shouldn't even be called for gists
      return false unless repository.is_a?(Repository)
      return false unless actor.is_a?(User) && actor.using_auth_via_user_programmatic_access?

      grant = actor.programmatic_access.grant_for_repository(repository)

      return false unless grant

      !grant.permissions.has_key?("workflows") || grant.permissions["workflows"] != :write
    end

    def public_key_from_oauth_without_workflow_write_scope
      actor.is_a?(PublicKey) &&
        actor.created_by_oauth_application? &&
        !actor.oauth_access?("workflow")
    end

    def public_key_created_by_unknown
      actor.is_a?(PublicKey) && actor.created_by_unknown?
    end
  end
end
