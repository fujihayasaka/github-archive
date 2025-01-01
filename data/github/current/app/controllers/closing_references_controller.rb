# typed: true
# frozen_string_literal: true

class ClosingReferencesController < AbstractRepositoryController
  include TimelineHelper
  include Issues::RateLimitsDependency
  include IssuesHelper

  rescue_from InvalidParameterError, with: :render_400

  before_action :writable_repository_required
  before_action :content_authorization_required, except: [:index, :show, :referencing_repositories]
  before_action :require_current_issue_or_pr
  before_action :resource_write_access_required
  before_action :writable_connection_ids_required, only: [:update]
  before_action :check_repository_write_access, only: [:update]
  before_action :check_selected_repository_write_access, only: [:update]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:referencing_repositories, :show]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:referencing_repositories, :show], optional: true

  VALID_SOURCE_TYPES = %w[ISSUE PULL_REQUEST].freeze
  REFERENCE_INDEX_LIMIT = 50
  BRANCH_INDEX_LIMIT = 50

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  # Edit the CloseIssueReferences and BranchIssueReferences of the current issue or pull request.
  def update
    GitHub.dogstats.time("closing_references_controller.update.time", tags: ["is_issue:#{issue?}"]) do
      close_issue_references = current_issue_or_pr.close_issue_references.manual
      connected_ids = close_issue_references.pluck(connected_by_key)

      connection_ids_to_remove = (connected_ids - proposed_connection_ids)
      connection_ids_to_add = proposed_connection_ids - connected_ids

      # Cross repo linking is only available in the Issue sidebar
      if sidebar_user_selection?
        connection_ids_to_remove = currently_visible_pull_requests(viewable_xrefed_items(connection_ids_to_remove)).pluck(:id)
        connection_ids_to_add = currently_visible_pull_requests(viewable_xrefed_items(connection_ids_to_add)).pluck(:id)

        branch_issue_references = current_issue_or_pr.linked_branches.for_repo(repository: selected_repository)
        branch_issue_reference_names = branch_issue_references.pluck(:branch_name)
        branch_names_to_remove = branch_issue_reference_names - proposed_branch_names
        branch_names_to_add = proposed_branch_names - branch_issue_reference_names

        # Check if branch exists on selected repository
        unless (branch_names_to_add + branch_names_to_remove - selected_repository.heads.names).empty?
          return render json: { error: "Invalid branch names" }, status: :unprocessable_entity
        end

        branch_names_to_remove.each do |name|
          current_issue_or_pr.linked_branches.find_by(branch_name: name).destroy
        end

        branch_names_to_add.each do |name|
          normalized_name = Git::Ref.normalize(name)

          BranchIssueReference.create!(
            issue: current_issue_or_pr,
            branch_name: normalized_name,
            branch_repository: selected_repository,
            creator: current_user
          )
        end
      end

      refs_to_remove = CloseIssueReference
        .where(source_key => current_issue_or_pr.id, connected_by_key => connection_ids_to_remove)
      refs_to_remove.destroy_all

      refs_to_add = if pull_request?
        selected_repository.issues.where(id: connection_ids_to_add)
      else
        selected_repository.pull_requests.where(id: connection_ids_to_add)
      end

      refs_to_add.each do |ref|
        current_issue_or_pr.close_issue_references
          .create(connected_by_key => ref.id, :source => :manual, :actor_id => current_user.id)
      end

      # Used to determine:
      #  - how common multi PR linking is
      analytics_event(
        category: "Development Menu",
        action: "Update",
        label: "removed_length:#{connection_ids_to_remove.length};added_length:#{connection_ids_to_add.length};is_issue:#{issue?}"
      )

      respond_to do |format|
        format.html do
          render partial: "issues/sidebar/show/references", locals: {
            issue: current_issue_or_pr.to_issue,
          }
        end
      end
    end
  end

  # List the closing references (issues, pull requests, or branches) for the current issue or pull request.
  def index
    GitHub.dogstats.time("closing_references_controller.index.time", tags: ["is_issue:#{issue?}"]) do
      references = current_issue_or_pr.close_issue_references

      # Items linked manually from sidebar
      manual_xref_pull_requests = viewable_xrefed_items(references.manual.pluck(connected_by_key))
      manual_xref_pull_requests_count_all_repos = manual_xref_pull_requests.count
      # Items linked by keyword
      xref_pull_requests = viewable_xrefed_items(references.xref.pluck(connected_by_key))
      # Items that the current user could link to the issue or pull request
      all_possible_references =
        CloseIssueReference.possible_closing_references_for(issue_or_pr: current_issue_or_pr,
                                                            viewer: current_user,
                                                            limit: REFERENCE_INDEX_LIMIT,
                                                            repository: selected_repository)

      manual_reference_ids_at_limit = CloseIssueReference
                                        .where(connected_by_key => all_possible_references.pluck(:id)).manual
                                        .group(connected_by_key)
                                        .having("count(*) >= ?", CloseIssueReference::MAX_MANUAL_REFERENCES)
                                        .pluck(connected_by_key)

      # The development menu on issues allows for selecting closing references from repositories other than the current one
      if issue?
        manual_xref_pull_requests = currently_visible_pull_requests(manual_xref_pull_requests)
        xref_pull_requests = currently_visible_pull_requests(xref_pull_requests)
        pull_requests = currently_visible_pull_requests(all_possible_references)
        all_branches = currently_visible_branches(selected_repository.heads.refs_with_default_first.take(BRANCH_INDEX_LIMIT))
        branch_issue_references_for_issue = current_issue_or_pr.linked_branches.for_repo(repository: selected_repository)
        manual_xref_branches = branches_for_references(branch_issue_references_for_issue.map(&:branch_name), all_branches)
        branches = all_branches - manual_xref_branches

        # Used to determine:
        #  - If REFERENCE_INDEX_LIMIT and BRANCH_INDEX_LIMIT are reasonable limits
        #  - How common cross repo linking is
        analytics_event(
          category: "Development Menu",
          action: query_param_linkable_items.present? ? "Search" : "List",
          label: "all_possible_references:#{all_possible_references.length};"\
            "all_branches:#{all_branches.length};"\
            "is_current_repo:#{selected_repository.id == current_repository.id};"\
            "is_issue:#{issue?}"
        )

        render Issues::References::LinkableItemsComponent.new(
          manual_xref_pull_requests: manual_xref_pull_requests,
          manual_xref_branches: manual_xref_branches,
          xref_pull_requests: xref_pull_requests,
          pull_requests: pull_requests,
          branches: branches,
          manual_reference_ids_at_limit: manual_reference_ids_at_limit,
          manual_xref_pull_requests_count_all_repos: manual_xref_pull_requests_count_all_repos,
          max_manual_reference_count: CloseIssueReference::MAX_MANUAL_REFERENCES
        ), layout: false
      else
        render partial: "issues/sidebar/references_menu_content", locals: {
          issue_or_pr: current_issue_or_pr,
          all_possible_references: all_possible_references,
          manual_reference_ids_at_limit: manual_reference_ids_at_limit,
          existing_xrefs: xref_pull_requests,
          existing_manual_references: manual_xref_pull_requests,
          max_manual_reference_count: CloseIssueReference::MAX_MANUAL_REFERENCES
        }
      end
    end
  end

  # List of repositories containing potential pull requests to link issue to
  def referencing_repositories # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.time("closing_references_controller.referencing_repositories.time") do
      return render_404 unless issue?

      # Unless it's a search query, sort the repo list by number of linked items they contain
      if query_param_repositories.present?
        repositories = repositories_query.writable_repositories
      else
        # Array containing repository ids of repositories that contain most linked items
        top_repositories = counts
          .sort_by { |_, count| -count }
          .take(10)
          .map { |repo_id, _| repo_id }

        # Check that these repositories are writable by current user
        repositories_with_count = writable_repositories(Repository.find(top_repositories))

        repositories = (writable_repositories([current_repository]) + repositories_with_count + repositories_query.writable_repositories).uniq.take(10)
      end

      # Used to determine if 100 is a reasonable limit for TargetRepositoryQuery.USER_REPO_LIMIT
      analytics_event(
        category: "Development Menu",
        action: "Repository List",
        label: "repositories_length:#{repositories.length};is_issue:#{issue?}"
      )

      render Issues::References::RepositoryComponent.new(
        repositories: repositories,
        counts: counts,
        issue: current_issue_or_pr
      ), layout: false
    end
  end

  # Render the sidebar partial
  def show
    respond_to do |format|
      format.html do
        render partial: "issues/sidebar/show/references", locals: {
          issue: current_issue_or_pr.to_issue,
        }
      end
    end
  end

  # This overrides the service catalog tagging defined in `service_mapping` to modify the catalog service tagging to properly associate to pull requests.
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    if current_repository && pull_request?
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/#{PULL_REQUESTS_TAG}"
    else
      super
    end
  end

  private

  # The repositories for which the current user has write access
  def repositories_query
    Branches::TargetRepositoryQuery.new(
      current_user: current_user,
      phrase: query_param_repositories,
      selected_repository: selected_repository,
      user_session: user_session,
      remote_ip: request.remote_ip,
      cap_filter: cap_filter,
      user_repos_first: true
    )
  end

  # The hash of repository.id to number of selected pull requests and branches for that repository.
  # Hash<Integer, Integer>
  memoize def counts
    references = current_issue_or_pr.close_issue_references.group_by do |close_issue_reference|
      Issue.find_by(pull_request_id: close_issue_reference.pull_request_id)&.repository_id
    end
    references = references&.transform_values(&:count)

    branches = current_issue_or_pr.linked_branches.group_by do |branch_issue_reference|
      branch_issue_reference.branch_repository_id
    end
    branches = branches.transform_values(&:count)

    counts = references.merge(branches) do |_key, close_issue_reference_count, branch_issue_reference_count|
      close_issue_reference_count + branch_issue_reference_count
    end
  end

  def writable_repositories(repositories)
    repositories.filter do |repo|
      repo.writable_by?(@current_user) && !repo.empty? && repo.writable?
    end
  end

  memoize def current_issue_or_pr
    # calling to_i on a string that is not an integer will return 0 which is not a valid id
    if !params[:source_id].respond_to?(:to_i) || params[:source_id].to_i == 0
      raise InvalidParameterError.new("Invalid source_id #{params[:source_id]} provided. Should be an integer.")
    end
    case params[:source_type]
    when "ISSUE"
      @current_issue_or_pr = current_repository.issues.find(params[:source_id].to_i)
    when "PULL_REQUEST"
      @current_issue_or_pr = current_repository.pull_requests.find(params[:source_id].to_i)
    else
      raise InvalidParameterError.new("Invalid source_type #{params[:source_type]} provided")
    end
  end

  def resource_write_access_required
    GitHub.dogstats.time("closing_references_controller.resource_write_access_required.time", tags: ["is_issue:#{issue?}"]) do
      if current_repository.private?
        return render_404 unless current_user_can_read_repo?
      end

      if selected_repository.private?
        return render_404 unless selected_repository.visible_and_readable_by?(current_user)
      end

      if pull_request?
        return head :unauthorized unless current_user_can_push?
      else
        return head :unauthorized unless current_issue_or_pr.labelable_by?(actor: current_user)
      end
    end
  end

  def check_repository_write_access
    head :unauthorized unless current_repository.writable_by?(current_user)
  end

  def check_selected_repository_write_access
    head :unauthorized unless selected_repository.writable_by?(current_user)
  end

  # check if the user has write access to the repositories which own the proposed connections
  def writable_connection_ids_required
    render_404 unless writable_xrefed_items(proposed_connection_ids).pluck(:id).sort == proposed_connection_ids.sort
  end

  def content_authorization_required
    authorize_content(:issue, repo: current_repository)
  end

  def require_current_issue_or_pr
    (pull_request? && params[:source_type] == "PULL_REQUEST") || issue?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def proposed_connection_ids
    [params[:connection_ids]].flatten.compact.map(&:to_i)
  end

  def proposed_branch_names
    [params[:branch_names]].flatten.compact
  end

  # Define which column on `close_issue_references` to treat as the source,
  # based on params[:source_type]
  def source_key
    pull_request? ? :pull_request_id : :issue_id
  end

  # Define which column on `close_issue_references` is the connected column,
  # based on params[:source_type]
  def connected_by_key
    pull_request? ? :issue_id : :pull_request_id
  end

  # Given a set of issue or PR ids, returns the ones the user is permitted to view
  def viewable_xrefed_items(ids)
    scope = pull_request? ? Issue : PullRequest

    scope.where(id: ids).select do |object|
      next if object.spammy? && !current_user&.site_admin?
      object.repository&.public? || object.repository&.visible_and_readable_by?(current_user)
    end
  end

  # Return the branches of the branch issue references
  #
  # branch_names = String[]
  # branches = Git::Ref[]
  def branches_for_references(branch_names, branches)
    branches.select do |branch|
      branch.name.in?(branch_names)
    end
  end

  # Given a set of issue or PR ids, returns the ones the user is permitted to write to
  def writable_xrefed_items(ids)
    scope = pull_request? ? Issue : PullRequest

    scope.where(id: ids).select do |object|
      next if object.spammy? && !current_user&.site_admin?
      object.repository&.writable_by?(current_user)
    end
  end

  # Returns repository the user has selected or defaults to the current repository if none selected
  memoize def selected_repository
    repo = if params[:repository_id].present?
      Repository.find_by(id: params[:repository_id])
    else
      current_repository
    end

    repo.network if current_repository
    repo
  end

  # Might be nil because the flag isn't flipped or we're not on an Issue
  def user_has_selected_repository?
    params[:repository_id].present?
  end

  # Query for repositories
  def query_param_repositories
    params[:repositories]
  end

  # Query for branches and pull requests to link to issue
  def query_param_linkable_items
    params[:linkable_items]
  end

  # Filter pull_requests by what is currently in view for the user, based on
  # their selected repository and an optional query.
  def currently_visible_pull_requests(pull_requests)
    return [] if !sidebar_user_selection?

    pull_requests = GitHub.dogstats.time("closing_references_controller.pull_requests_for_repo.time") do
      pull_requests.filter do |pull_request|
        next if pull_request.nil?
        # The pull request exists in the selected repository and one its applicable properties matches the user's search query
        selected_repository.pull_requests.exists?(id: pull_request.id) && pull_request_matches_query?(pull_request)
      end
    end
  end

  # Filter branches by what is currently in view for the user, based on
  # their selected repository and an optional query.
  def currently_visible_branches(branches)
    return [] if !sidebar_user_selection?

    GitHub.dogstats.time("closing_references_controller.currently_visible_branches.time") do
      branches.filter do |branch|
        !selected_repository.pull_requests.exists?(head_ref: branch.name) &&
          branch.name != selected_repository.default_branch &&
          branch_matches_query?(branch)
      end
    end
  end

  # Given a pull request, returns whether its name, pull request number, or branch name matches the query.
  def pull_request_matches_query?(pull_request)
    return true unless query_param_linkable_items.present?
    pull_request.title.include?(query_param_linkable_items) ||
      pull_request.number.to_s.include?(query_param_linkable_items) ||
      pull_request.display_head_ref_name.include?(query_param_linkable_items)
  end

  # Given a pull request, returns whether its name, pull request number, or branch name matches the query.
  def branch_matches_query?(branch)
    return true unless query_param_linkable_items.present?
    branch.name.include?(query_param_linkable_items)
  end

  def sidebar_user_selection?
    issue? && user_has_selected_repository?
  end

  def pull_request?
    current_issue_or_pr.is_a?(PullRequest)
  end

  def issue?
    current_issue_or_pr.is_a?(Issue) && params[:source_type] == "ISSUE"
  end

  def render_400(error)
    render json: { error: error.message }, status: :bad_request
  end
end
