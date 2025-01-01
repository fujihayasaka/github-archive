# typed: false
# frozen_string_literal: true

# Shared controller methods for commiting a change from the web interface
# Depends on `#current_user`, `#current_repository`
module WebCommitControllerMethods
  include GitHub::UTF8

  def self.included(base)
    base.helper_method :commit_message_placeholder
  end

  private

  # Retrieves the optimal base repository and branch for the current user and given path.
  #
  # "Base repository" will either be a fork of the current repository, if the user
  # has an existing fork in network, or the current repository.
  #
  # Returns a two element Array where the first element is the base Repository and
  # the second element is the String base branch name.
  def base_repository_and_branch
    base = current_repository.base_branch(params[:name], current_user)
    base_branch, base_user = base.split(":").reverse
    base_repository = base_user ? current_repository.find_fork_in_network_for_user(base_user) : current_repository

    [base_repository, base_branch]
  end

  # Filter before new, edit, and delete actions
  #
  # For users who don't have push access to the given branch, checks if they have
  # an existing fork that contains the given branch. If not, renders view that
  # directs them to fork the repo or update their existing fork, since we don't
  # want to perform create or update operations on a GET request.
  def confirm_forking
    return if request.post?
    return if (params[:action] == "edit" || params[:action] == "new" || params[:action] == "delete") && code_view_enabled?

    forking = updating = false
    unless current_user_can_push_to_ref?(params[:name])
      user_fork = current_repository.find_fork_in_network_for_user(current_user)
      forking = user_fork.blank?
      updating = !forking && !user_fork.refs.exist?(params[:name])
    end

    if forking || updating
      render "web_commit/edit_confirmation"
    end
  end

  # Filter before new, edit, and delete actions
  #
  # For repositories that are locked on migration, renders view that notifies the
  # user that they are unable to edit this repository during the migration.
  def require_repository_not_migrating
    if current_repository.locked_on_migration?
      render "web_commit/edit_confirmation"
    end
  end

  def web_commit_info(commit_oid, save_url, branch)
    dco_signoff_enabled = current_repository.dco_signoff_enabled?

    unless current_user_can_push_to_ref?(tree_name) || request.post?
      add_csrf_token(request.fullpath, :post)
      user_fork = current_repository.find_fork_in_network_for_user(current_user)
      should_fork = user_fork.blank?
      should_update = !should_fork && !user_fork.refs.exist?(params[:name])
    end

    locked_on_migration = current_repository.locked_on_migration?

    unless should_fork || should_update || locked_on_migration
      return false unless establish_target_repository(branch: branch, create_fork: request.post?, update_fork: request.post?)
      if @target_repo != current_repository
        user_fork = @target_repo
      end
    end

    if user_fork.present?
      forked_repo = { id: user_fork.id, name: user_fork.name, owner: user_fork.owner.display_login }
    end

    branch_protected = current_repository.branch_protected?(tree_name)
    rulesets_protected = current_repository&.rulesets_for_ref("refs/heads/#{branch}").any?

    # determines if banner should show at all
    should_warn = !current_repository.supports_protected_branches? && (rulesets_protected || branch_protected)

    if should_warn
      organization = current_repository.owner.organization?

      # determines to whom to show the banner to
      show_cta = !current_repository.supports_protected_branches? &&
        (rulesets_protected || branch_protected) &&
        (organization || (!organization && current_repository.adminable_by?(current_user)))

      # implicitly relies on the rulesets upsell experience as a whole rather than any one FF
      ask_admin = organization && !owner&.adminable_by?(current_user)

      feature = if rulesets_protected
        MemberFeatureRequest::Feature::Rulesets
      else
        MemberFeatureRequest::Feature::ProtectedBranches
      end

      protection_not_enforced_info = {
        editRepositoryRulesetsPath: repository_rulesets_path,
        editRepositoryBranchesPath: edit_repository_branches_path(current_repository.owner, current_repository),
        organization: organization,
        branchProtected: branch_protected,
        rulesetsProtected: rulesets_protected,
        upsellCtaInfo: {
          visible: show_cta,
          cta: {
            showUpgradeButton: current_repository.owner.adminable_by?(current_user),
            askAdmin: ask_admin,
            ctaPath: organization ? helpers.settings_org_plans_path(current_repository.owner) : new_move_work_path(current_repository.owner, repository: current_repository, feature: feature.to_s),
          }
        },
        featureRequestInfo: {
          showFeatureRequest: !GitHub.enterprise? && organization && !owner.adminable_by?(current_user),
          alreadyRequested: organization && MemberFeatureRequest.already_requested?(current_user, owner, feature),
          featureName: feature.to_s,
          requestPath: org_member_feature_requests_path(org: owner.display_login),
        }
      }
    end

    {
      authorEmails: current_user.author_emails.map { |user_email| current_user.remove_shortcode(user_email) },
      canCommitStatus: current_repository.can_commit_to_branch_status(current_user, tree_name),
      commitOid:  commit_oid,
      dcoSignoffEnabled: dco_signoff_enabled,
      dcoSignoffHelpUrl: dco_signoff_enabled ? DcoSignoffHelper::dco_signoff_help_url : nil,
      defaultEmail: if !current_user.author_emails.any? && dco_signoff_enabled
                      current_user.git_author_email
                    else
                      current_user.default_author_email(current_repository)
                    end,
      defaultNewBranchName: current_repository.heads.temp_name(topic: "patch", prefix: current_user.display_login),
      guidanceTask: params[:guidance_task],
      saveUrl: save_url,
      forkedRepo: forked_repo,
      repoHeadEmpty: current_repository.heads.empty?,
      shouldFork: should_fork,
      shouldUpdate: should_update,
      lockedOnMigration: locked_on_migration,
      pr: params[:pr],
      protectionNotEnforcedInfo: protection_not_enforced_info,
      suggestionsUrlMention: suggestions_path(repository: current_repository, user_id: current_repository.owner, mention_suggester: 1),
      suggestionsUrlIssue: suggestions_path(repository: current_repository, user_id: current_repository.owner, issue_suggester: 1),
      suggestionsUrlEmoji: emoji_suggestions_path
    }
  end

  # Internal: Establish a default @target_repo and lazily fork the current
  # repository if we can't push
  def establish_target_repository(branch:, create_fork:, update_fork:)
    return unless branch
    @target_repo = current_repository
    auto_fork(branch: branch, create_fork: create_fork, update_fork: update_fork) unless current_user_can_push_to_ref?(branch)
    if params[:same_repo] && params[:target_branch] != branch
      # if you're creating a branch, check if you have full write permission on the repo
      if @target_repo.pushable_by?(current_user)
        true
      else
        log_establish_target_repository_failure
        @target_repo = nil
        false
      end
    else
      if @target_repo && @target_repo.pushable_by?(current_user, ref: branch)
        # it is ok still, as long as you have fork collab permissions
        true
      else
        log_establish_target_repository_failure
        @target_repo = nil
        false
      end
    end
  end

  def log_establish_target_repository_failure
    GitHub.logger.info(
      "Failed to establish target repository",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.request_id" => GitHub.context[:request_id],
      "gh.actor.id" => current_user.id,
      "gh.repo.owner.id" => current_repository.owner.id,
      "gh.repo.id" => @target_repo ? @target_repo.id : nil,
    )
  end

  # Internal: Fork the current repository so the current user
  # can propose a change.
  #
  # branch - the branch for this proposed change - necessary
  #          in case a fork already exists, so this branch
  #          will be pulled over to the old fork
  # create_fork - optional Boolean for creating a fork
  #
  # Also updates the target repository for the file form.
  def auto_fork(branch:, create_fork:, update_fork:)
    repo = current_repository
    user = current_user

    if repo.network_has_fork_for?(user)
      # repo is already forked - ensure the target branch exists
      # the fork may be old and missing newer branches
      ref = repo.heads.find(branch)
      @forked_repo = repo.find_fork_in_network_for_user(user)

      if ref && @forked_repo.exists_on_disk? && !@forked_repo.refs.exist?(branch) && update_fork
        @forked_repo.fetch_commits_from(ref, user: user)
      end
    elsif create_fork
      # make a new fork
      @forked_repo, @forked_reason, errors = repo.fork(forker: user)

      if !@forked_repo
        GitHub.logger.error(
          "Failed to auto fork repository for user",
          "exception.message" => "#{@forked_reason}:#{errors}",
          "exception.type" => "AutoForkForkingError",
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.request_id" => GitHub.context[:request_id],
          "gh.actor.id" => user.id,
          "gh.repo.owner.id" => repo.owner.id,
          "gh.repo.id" => repo.id,
        )
      end
    else
      return
    end

    @target_repo = @forked_repo
  end

  # Internal: Set the commit for the new/edit/delete file form
  #
  # new - is this for a new file?
  #       (optional, defaults to false)
  def set_form_commit(new = false)
    if ref = current_repository.heads.find(tree_name)
      @last_commit = ref.target_oid
    elsif new && current_repository.heads.empty?
      # creating a file in an empty repo is allowed
      @last_commit = ""
    end
  end

  # Internal: Combine message and description from params into a full commit message.
  #
  # action - action being performed (new, edit, delete)
  #
  # Returns the String commit message
  def commit_message_from_request(action)
    message =
      if params[:message].present?
        params[:message]
      elsif params[:placeholder_message].present?
        params[:placeholder_message]
      else
        commit_message_placeholder(action)
      end

    parts = [message, params[:description]]
    parts << DcoSignoffHelper::dco_signoff_text(current_user, params) if current_repository.dco_signoff_enabled?
    parts.reject(&:blank?).join("\n\n")
  end

  # Public: placeholder text for the commit message
  #
  # action - action being performed (new, edit, or delete)
  #
  # Returns the String commit message placeholder
  def commit_message_placeholder(action)
    send("#{action}_commit_message_placeholder")
  end

  # Internal: commit message placeholder for file edits
  #
  # used by commit_message_placeholder
  def edit_commit_message_placeholder
    filename = @filename.blank? ? path_string : @filename
    "Update #{filename}".dup.force_encoding("UTF-8").scrub!
  end

  # Internal: commit message placeholder for new files
  #
  # used by commit_message_placeholder
  def new_commit_message_placeholder
    filename = @filename.blank? ? "new file" : @filename
    "Create #{filename}".dup.force_encoding("UTF-8").scrub!
  end

  # Internal: commit message placeholder for deleting files
  #
  # used by commit_message_placeholder
  def delete_commit_message_placeholder
    filename = @filename.blank? ? path_string : @filename
    "Delete #{filename}".dup.force_encoding("UTF-8").scrub!
  end

  # Internal: Check for a conflict (repo change)
  #
  # path        - file path for proposed change
  # old_oid     - commit oid when proposed change was submitted
  # current_oid - current commit oid where proposed change will take place
  #               (optional: will default to current branch location)
  #
  # Sets flash error
  # Returns Boolean result
  def change_conflict?(path, old_oid, current_oid = commit_sha)
    return false if params[:quick_pull] # quick pull creates a new branch, so it doesn't matter
    return false unless current_oid != old_oid
    return false unless detect_conflict(path, old_oid, current_oid)

    @contents = params[:value]
    @allow_contents_unchanged = true
    commit = current_repository.commits.find(current_oid)
    user_login = commit&.author&.display_login || commit&.committer&.display_login || :Someone
    url = compare_path(current_repository, "#{old_oid}...#{current_oid}")

    flash.now[:error] = \
      "#{user_login} has committed since you started editing. " \
      "<a href='#{url}'>See what changed</a>".html_safe # rubocop:disable Rails/OutputSafety

    true
  end

  # Internal: Actually check for a conflict
  #
  # A "conflict" is any change to the actual path in question
  #
  # path        - file path for proposed change
  # old_oid     - commit oid when proposed change was submitted
  # current_oid - current commit oid where proposed change will take place
  #
  # Returns true if conflict was detected, false otherwise
  def detect_conflict(path, old_oid, current_oid)
    return true unless old_oid && current_oid

    diff = GitHub::Diff.new(current_repository, old_oid, current_oid)

    encoded_path = utf8(path)

    diff.requested_paths.any? do |delta_path|
      encoded_delta_path = utf8(delta_path)
      encoded_delta_path == path ||                        # Path matches a changed file
        encoded_delta_path =~ /\A#{Regexp.escape(path)}\// # Path matches parent directory of a changed file
    end
  end

  # Internal: Commit a change (create, update, or destroy)
  #
  # repo    - repo where change is actually made
  # user    - user making change
  # branch  - branch name for this commit
  # old_oid - commit oid when proposed change was submitted
  # files   - Hash of filename => data pairs.
  # message - message to use for the commit
  #
  # Returns a tuple of `(commit ID, branch name, error message, full error)` or `nil`.
  def commit_change_to_repo_for_user(repo, user, branch, old_oid, files, message)
    # We double check that email belongs to the user in
    # CommitsCollection#create, but we enforce this here as well.
    author_email = params[:author_email]
    return unless author_email.nil? || user.emails.verified.pluck(:email).include?(author_email)

    if params[:quick_pull].blank?
      ref = repo.heads.find_or_build(branch)
    elsif params[:same_repo]
      # commit this change to a temp branch and send to pull-request page
      branch = params[:target_branch].to_s
      branch = Git::Ref.normalize(branch) || repo.heads.temp_name(topic: "patch", prefix: user.display_login)
      branch = repo.heads.temp_name(topic: branch) if repo.heads.exist?(branch)
      ref = repo.heads.find_or_build(branch)
    else
      base_ref = quick_pull_base_ref(params[:quick_pull], branch)
      branch = repo.heads.temp_name(topic: "patch")
      ref = repo.fetch_commits_from(base_ref, new_ref_name: branch, user: user)
    end

    pull_request = pull_request_from_pr_param(repo, ref)

    commit, branch, err_msg, full_error = repo.commit_change_for_user(
      author: user,
      author_email: author_email,
      before_oid: old_oid,
      branch: branch,
      files: files,
      message: message,
      pull_request: pull_request,
      sign: true,
    )

    @hook_out = err_msg if err_msg
    [commit, branch, err_msg, full_error] if commit || err_msg
  end

  # Internal: get the base ref for this quick pull
  #
  # base   - String representing the quick-pull base
  #          example: ymendel:cloaked-octo-lana
  # branch - String branch name
  #
  # Returns a Ref
  def quick_pull_base_ref(base, branch)
    return unless base

    repo = nil

    if base == "1"
      repo = current_repository.parent
    else
      user = base.split(":", 2).first
      repo = current_repository.find_fork_in_network_for_user(user)
    end

    return unless repo

    repo.heads.find(branch)
  end

  def increment_quick_pull_error_stats
    if cross_repo_quick_pull?
      GitHub.dogstats.increment("pull_request", tags: ["type:quick", "error:fail", "repo:cross"])
    elsif same_repo_quick_pull?
      GitHub.dogstats.increment("pull_request", tags: ["type:quick", "error:fail", "repo:same"])
    end
  end

  def increment_quick_pull_commit_stats
    if cross_repo_quick_pull?
      GitHub.dogstats.increment("pull_request", tags: ["type:quick", "repo:cross", "action:commit"])
    elsif same_repo_quick_pull?
      GitHub.dogstats.increment("pull_request", tags: ["type:quick", "repo:same", "action:commit"])
    end
  end

  def increment_quick_pull_start_stats
    if cross_repo_quick_pull?
      GitHub.dogstats.increment("pull_request", tags: ["type:quick", "repo:cross", "action:start"])
    elsif same_repo_quick_pull?
      GitHub.dogstats.increment("pull_request", tags: ["type:quick", "repo:same", "action:start"])
    end
  end

  # Internal: Boolean check for whether pull request target repo is different
  # from the current repository
  def cross_repo_quick_pull?
    @target_repo != current_repository
  end

  # Internal: Boolean check for whether pull request base and head branch belong
  # to the same repo
  def same_repo_quick_pull?
    @target_repo == current_repository && !params[:target_branch].blank? && params[:target_branch] != @branch
  end

  PR_PARAM_REGEXP = %r{\A/(?<name_with_owner>[\w.-]+/[\w.-]+)/pull/(?<number>\d+)\z}

  # Internal: Parse :pr param into [name_with_owner, number] tuple.
  def parsed_pr_from_params
    return unless match = PR_PARAM_REGEXP.match(params[:pr])
    [match[:name_with_owner], match[:number].to_i]
  end

  # Internal: Boolean check whether :pr param contains a valid pull request url
  def redirect_back_to_pr?
    !!parsed_pr_from_params
  end

  # Internal: Use this instead of params[:pr] as it will only return the URL when it's valid
  def redirect_back_to_pr_url
    params[:pr] if redirect_back_to_pr?
  end

  # Internal: Returns the PullRequest associated with params[:pr], or `nil` if
  # the param is invalid or does not match the supplied `repo` and `ref`.
  def pull_request_from_pr_param(repo, ref)
    return unless (name_with_owner, number = parsed_pr_from_params)
    return unless name_with_owner == repo.name_with_display_owner
    pull_request = repo.issues.where(number: number).first&.pull_request
    return pull_request if pull_request&.head_ref == ref.name
  end

  # Internal: clean out the params hash
  #
  # Sets blank params to nil
  def clean_params
    params[:quick_pull] = nil if params[:quick_pull]&.blank?
    true
  end
end
