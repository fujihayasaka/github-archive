# typed: false
# frozen_string_literal: true

module ActionsControllerMethods
  include GitHub::Memoizer

  FILTER_FIELDS = [:workflow, :actor, :branch, :event, :is, :created]
  WORKFLOWS_PER_PAGE = 30
  WORKFLOWS_FIRST_PAGE = 10
  REQUIRED_WORKFLOWS_FIRST_PAGE = 5

  # Query string of passed in filters
  def workflow_query
    params[:query] || ""
  end

  # Query string of query to filter workflow list
  def workflow_list_filter
    Addressable::URI.unescape(params[:q]) || ""
  end

  # Hash of passed in workflow filters
  def workflow_run_filters
    return @_workflow_run_filters if defined?(@_workflow_run_filters)
    query = workflow_query
    parsed_query = Search::ParsedQuery.parse(query, terms: FILTER_FIELDS)
    filters_array = parsed_query.
      select { |param| param.is_a?(Array) }. # filter out non-qualifier nodes
      map { |param| param.first(2) } # negated params get an extra boolean in the array
    filters = Hash[filters_array]

    if params[:workflow] && !filters[:workflow]
      # Fall back to query string parameter to preserve back-compat
      filters[:workflow] = params[:workflow]
    end

    @_workflow_run_filters = filters
  end

  def workflow_name_query
    workflow_run_filters[:workflow]
  end

  def selected_workflow_name
    selected_workflow&.name
  end

  def selected_workflow_filename
    selected_workflow&.filename
  end

  def selected_workflow
    return @workflow if defined?(@workflow)
    return required_workflows.first if params[:workflow_file_name].nil? && show_only_required_workflows?
    return @workflow = nil unless params[:workflow_file_name]

    is_lab = params[:lab] == "true"
    @workflow = current_repository.workflows.find_from_filename(params[:workflow_file_name], is_lab: is_lab)
  end

  def selected_workflow_run
    return @workflow_run if defined?(@workflow_run)
    return @workflow_run = nil unless params[:workflow_run_id]

    @workflow_run = current_repository.workflow_runs.find_by(id: params[:workflow_run_id])
  end

  def required_workflows
    return @required_workflows if defined?(@required_workflows)

    @required_workflows = workflows(fetch_required_workflows: true)
  end

  # First page of workflows
  def workflows(fetch_required_workflows: false)
    workflows_first_page = get_workflow_firstpage_count(fetch_required_workflows)
    unbound_workflows(fetch_required_workflows: fetch_required_workflows).paginate(page: 1, per_page: workflows_first_page)
  end

  def paginated_workflows(current_page, fetch_required_workflows: false)
    return workflows(fetch_required_workflows: fetch_required_workflows) if current_page == 1
    paginate_after_first_page(current_page, fetch_required_workflows: fetch_required_workflows)
  end

  def actions_enabled_for_repo?
    render_404 unless (GitHub.actions_enabled? && !current_repository.actions_disabled?) || show_only_required_workflows?
  end

  def show_only_required_workflows?
    current_repository.actions_disabled? && !current_repository.actions_disabled_by_owner? && current_repository.workflows.required.not_deleted.any?
  end

  def should_show_selected_workflow_run?
    render_404 unless !show_only_required_workflows? || (show_only_required_workflows? && selected_workflow_run&.required_workflow_run? && !selected_workflow_run&.workflow&.deleted?)
  end

  def selected_category
    return @selected_category if defined?(@selected_section)
    return @selected_category = :discover_workflows if !params[:category] || params[:category] == "discover"

    return @selected_category = :all_workflow_templates if params[:category] == "none"
    return @selected_category = :owner if params[:category] == "owner"

    @selected_category = params[:category]
  end

  def show_runners_view?
    return false if GitHub.enterprise?
    return false unless logged_in?
    return false unless current_repository.writable_by?(current_user)

    true
  end

  def show_attestations_view?
    return false if GitHub.enterprise?
    actor = current_repository.public? ? current_user : current_repository.owner
    return false unless GitHub.flipper[:attestations_ux].enabled?(actor)

    true
  end

  memoize def allow_pinning?
    Actions::PinnedWorkflow.allow_pinning?(current_repository, current_user)
  end

  def strip_branch_prefix(head_branch)
    head_branch.sub(%r{\Arefs/heads/|refs/tags/}, "")
  end

  private

  def unbound_workflows(fetch_required_workflows: false)
    return unbound_workflows_for_pinning if current_repository.feature_enabled?(:actions_workflow_list_pinning)

    workflows_to_process = if fetch_required_workflows
      current_repository.workflows.not_deleted.required
    else
      current_repository.workflows.not_deleted.non_required
    end

    workflows = if !site_admin? && !current_user&.spammy?
      workflows_to_process.viewable_workflows
    elsif !site_admin? && current_user&.spammy?
      workflows_to_process.not_deleted.spammer_viewable_workflows(current_user.id)
    else
      workflows_to_process
    end

    workflows.with_valid_path.order(Arel.sql("CAST(name as CHAR)"))
  end

  # Returns all workflows to be shown to user, used behind flag :actions_workflow_list_pinning
  def unbound_workflows_for_pinning
    workflows_to_process = if show_only_required_workflows?
      current_repository.workflows.not_deleted.required
    else
      current_repository.workflows.not_deleted
    end

    workflows = if !site_admin? && !current_user&.spammy?
      workflows_to_process.viewable_workflows
    elsif !site_admin? && current_user&.spammy?
      workflows_to_process.not_deleted.spammer_viewable_workflows(current_user.id)
    else
      workflows_to_process
    end

    # Sort pinned workflows to the top of the list
    # Deleted workflows are not shown, so we can order by `state` to sort disabled workflows to the bottom of the list
    workflows.with_valid_path
      .joins("
        LEFT JOIN pinned_workflows
          ON workflows.id=pinned_workflows.workflow_id
          AND workflows.repository_id=pinned_workflows.repository_id
      ")
      .order(Arel.sql("pinned_workflows.workflow_id IS NULL, state, CAST(name as CHAR)"))
      .preload(:pinned_workflow)
  end

  # Need this workaround because first page has lesser number of workflows that other pages
  def paginate_after_first_page(current_page, fetch_required_workflows: false)
    workflows_first_page = get_workflow_firstpage_count(fetch_required_workflows)

    WillPaginate::Collection.create(current_page, WORKFLOWS_PER_PAGE) do |pager|
      # inject the result array into the paginated collection:
      pager.replace(unbound_workflows(fetch_required_workflows: fetch_required_workflows).offset(workflows_first_page + (current_page - 2) * WORKFLOWS_PER_PAGE).limit(WORKFLOWS_PER_PAGE))
      unless pager.total_entries
        # the pager didn't manage to guess the total count, do it manually
        pager.total_entries = unbound_workflows(fetch_required_workflows: fetch_required_workflows).count
      end
    end
  end

  # Pages count needs to be done manually because of the offset
  def workflow_pages_count(fetch_required_workflows: false)
    workflows_first_page = get_workflow_firstpage_count(fetch_required_workflows)
    if workflows(fetch_required_workflows: fetch_required_workflows).count <= workflows_first_page
      @workflow_pages_count = 1
    else
      @workflow_pages_count = ((workflows(fetch_required_workflows: fetch_required_workflows).count - workflows_first_page) / WORKFLOWS_PER_PAGE.to_f).ceil + 1
      # As we show selected workflow on top for paginated pages, we need to hide "Show more workflows" button
      # for cases when there is one workflow on the last page and it is the selected one
      if selected_workflow.present? && !selected_workflow.required? && ((workflows(fetch_required_workflows: fetch_required_workflows).count - workflows_first_page) % WORKFLOWS_PER_PAGE == 1)
        if paginated_workflows(@workflow_pages_count, fetch_required_workflows: fetch_required_workflows).include?(selected_workflow)
          @workflow_pages_count -= 1
        end
      end
    end
    @workflow_pages_count
  end

  # Show the link only if the source repo's default branch contains the workflow file
  def show_link_to_required_workflow?
    required_workflow_source_repo = Repository.find_by(id: selected_workflow&.imposer_repository_id)
    return false if required_workflow_source_repo.nil?

    default_branch_sha = required_workflow_source_repo.default_branch_ref&.target_oid
    return false unless default_branch_sha.present? && required_workflow_source_repo.tree_entry(default_branch_sha, selected_workflow&.path).present?

    required_workflow_source_repo.pullable_by?(current_user)
  end

  def get_workflow_firstpage_count(fetch_required_workflows)
    fetch_required_workflows ? REQUIRED_WORKFLOWS_FIRST_PAGE : WORKFLOWS_FIRST_PAGE
  end
end
