# typed: false
# frozen_string_literal: true

class GitContentController < AbstractRepositoryController
  include Gitkeeper
  before_action :ask_the_gitkeeper
  before_action :try_to_expand_path,  only: [:show, :raw]

  def controller # rubocop:todo GitHub/UseRestfulActions
    self # Required for RelativeLinkFilter (in #basic_html_context)
  end

  def current_repository # rubocop:todo GitHub/UseRestfulActions
    super # We need current_repository to be public for RelativeLinkFilter (in #default_html_filter_context)
  end

  def expand # rubocop:todo GitHub/UseRestfulActions
    redirect_to "/#{owner.display_login}/#{current_repository}/#{params[:controller]}/#{default_tree}", status: 301
  end

  rescue_from GitRPC::InvalidObject, GitRPC::NoSuchPath do |e|
    render_404(e)
  end

  rescue_from GitRPC::ConnectionError do |_e|
    render_offline
  end

  def show
    raise NotImplementedError
  end

  def raw # rubocop:todo GitHub/UseRestfulActions
    raise NotImplementedError
  end

  protected

  # If the request is for a branch that does not exist, attempt to use
  # RepositoryBranchRename records and redirect to the equivalent URL
  # with the new branch name.  This is shared by FilesController (for
  # trees) and BlobController (for blobs)
  def redirect_for_missing_branch
    # See `AbstractRepositoryController#set_path_and_name`. This is not
    # set if a branch is not found.
    return if params[:branch].present?
    return unless params[:name].present?

    branch_and_path = [params[:name].presence, params[:path].presence].concat.join("/").chomp("/")

    result = RepositoryBranchRename::Detector.call(
      repository: current_repository,
      full_path: branch_and_path
    )

    return unless result.includes_renamed_branch? && database_errors.length == 0

    GlobalInstrumenter.instrument "repository.missing_branch_redirect",
      repository: current_repository,
      actor: current_user,
      missing_branch_was_master: result.missing_branch_was_master

    redirect_to(
      { name: result.redirect_branch, path: result.path },
      notice: result.redirect_notice
    )
  end

  private

  helper_method :tree_commit_key

  UNTRACKED_STATES = %w(down offline content_noexist).freeze
  TRACKED_STATES = %w(move_locked billing_locked locked migrating nothing importing empty forking mirroring cloning nobranch).freeze
  SPECIAL_STATES = [].concat(UNTRACKED_STATES, TRACKED_STATES)

  def tree_commit_key
    parts = [
      AvatarHelper::CACHE_VERSION,
      "v13",
      "commit",
      current_repository.name_with_display_owner,
      commit_sha, path_string
    ]
    git_content_cache_key :tree, parts
  end

  # Generates a cache key for Blob and Tree view content.  This lets you break
  # both of them at the same time if desired.
  def git_content_cache_key(prefix, pieces)
    key = "#{prefix}:v22:#{Digest::SHA256.hexdigest(pieces.join(":"))}"
    return key unless GitHub.multi_tenant_enterprise?

    # We want to refresh the cache every 30 minutes
    time_key = Time.now.to_i / 30.minutes.to_i
    "#{key}:#{time_key}"
  end

  # There are many reasons we may not be able to show a repository's code.
  # This filter goes through all possible scenarios and renders the
  # appropriate template if we cannot show the code.
  #
  # nonexist      - The content straight up doesn't exist. Or has been deleted.
  # empty         - The repo is empty and should be. Show the Next Step page.
  # importing     - The repo is empty and an import is in progress and we know
  #                 where Porter is. Redirect to the import progress page.
  # locked        - The repo is locked due to a long-running operation (rename).
  # network_move  - The repo is locked in preparation for extraction into a new
  #                 network.
  # down          - The repo looks like it's been pushed to, but doesn't have git.
  # offline       - The repo is empty, but it shouldn't be. Something is amiss.
  # forking       - The repo is still trying to fork.
  # mirroring     - The repo is still trying to mirror.
  # nothing       - The current_user doesn't exist or can't push to the repo and
  #                 there's nothing to show them (one of the above states).
  # blank         - There's no git data, the user needs to push it up.
  #
  # You can fake each of these states with params[:fakestate] equal to the
  # words listed above.
  #
  # Returns nothing.
  def ask_the_gitkeeper
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    repo = current_repository
    state = params[:fakestate].present? && real_user_site_admin? ? params[:fakestate] : nil

    # if state has been passed as an argument it is an override,
    # return early with the correct state rendering
    unless state.nil?
      return render_state(repo: repo, state: state) if SPECIAL_STATES.include?(state)
    end

    check_cache = request.get?
    tags = ["method:gitkeeper_state"]
    tags << "check_cache:#{check_cache}"
    state = GitHub.dogstats.distribution_time("gitkeeper.time", tags: tags) do
      gitkeeper_state(repo, check_cache: check_cache)
    end

    # At this point state should match a case in SPECIAL_STATES or be nil,
    render_state(repo: repo, state: state)

  # don't use render_state method in rescue's since it will add time
  rescue ::GitRPC::InvalidRepository, GitRPC::Timeout
    render_offline("down")
  rescue ::GitRPC::RepositoryOffline, GitHub::DGit::UnroutedError, GitHub::DGit::InsufficientQuorumError => e
    GitHub.logger.error(
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.spokes.spec" => repo.dgit_spec
    )
    render_offline
  ensure
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    state = state.nil? ? "pass" : state
    tag = "state:#{state}"
    GitHub.dogstats.distribution("git_content_controller.ask_the_gitkeeper", (end_time - start_time) * 1000, tags: [tag, "gitkeeper_version:new"])
  end

  def render_state(repo: current_repository, state: nil)
    # return early if state is nil, otherwise we should be in a valid state
    return if state.nil?
    # Since all DD calls use the state as a tag, this has been broken out into it's own method
    send_stats(state)

    # case switch may be marginally faster here.... it's the little things
    case state
    when "move_locked"
      render "repositories/states/network_move"
    when "billing_locked"
      render "repositories/states/billing_locked"
    when "locked"
      render "repositories/states/locked"
    when "nothing"
      render "repositories/states/nothing"
    when "importing"
      redirect_to repository_import_path(repository: repo, user_id: repo.owner.display_login)
    when "blank_slate"
      render "graphs/blank_slate"
    when "cloning"
      render "repositories/states/cloning"
    when "empty"
      render "repositories/states/empty"
    when "down"
      render_offline("down")
    when "offline"
      render_offline
    when "forking"
      render "repositories/states/forking"
    when "mirroring"
      render "repositories/states/mirroring"
    when "nobranch"
      render "repositories/states/nobranch"
    when "content_nonexist"
      render_404
    end
  end

  def send_stats(state)
    # don't send stats if the repo is in one of the non-states, or if state is nil
    return if state.nil? || UNTRACKED_STATES.include?(state)
    GitHub.dogstats.increment("repo", tags: ["action:ask_the_gitkeeper", "state:#{state.dasherize}"])
  end

  # Find out if a bad default branch was specified. This will only be the case
  # if these 3 conditions are true:
  #
  # 1. The default branch was specified in the request
  # 2. The repository has at least one branch
  # 3. The repository does not have a branch with the name that was specified
  #
  # Returns true if a bad default branch was specified, false otherwise.
  def bad_default_branch_ref?
    (tree_name == current_repository.default_branch) &&
    !current_repository.heads.empty? &&
    !current_repository.heads.include?(tree_name)
  end

  # If the repository's default branch doesn't exist, elect a new default branch
  # now instead of 404'ing. This is a weird thing to happen, since a new default
  # branch should be chosen when the old one is deleted. It sometimes happens
  # though, likely due to failed jobs or other error conditions.
  #
  # This should live in the model.
  #
  # Returns truthy if a new branch was selected and a commit is available, false
  # otherwise.
  def repair_bad_default_branch_ref
    return unless bad_default_branch_ref?

    default_branch =
      if current_repository.heads.include?("master")
        "master"
      else
        current_repository.heads.first.name
      end
    current_repository.update_default_branch default_branch
    @tree_name = default_branch
    @current_commit = current_repository.commit_for_ref(default_branch)
    @commit_sha = @current_commit.oid if @current_commit
  end

  def try_to_expand_path
    if params[:controller] == "tree" && params[:action] == "show"
      # https://github.com/defunkt/cijoe shows the default tree
      return if params[:name].blank?

      # https://github.com/defunkt/cijoe/tree/master => https://github.com/defunkt/cijoe
      if params[:name] == default_tree && params[:path].blank?
        return redirect_to "/#{owner.display_login}/#{current_repository}", status: 301
      end
    end

    return unless params[:name].blank? && params[:raw].blank?
    redirect_to "/#{owner.display_login}/#{current_repository}/#{params[:controller]}/#{default_tree}", status: 301
  end

  def default_tree
    current_repository.default_branch rescue "master"
  end
end
