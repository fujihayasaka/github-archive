# typed: false
# frozen_string_literal: true

module ProjectControllerActions
  PAGE_SIZE = 30
  LARGE_MIGRATION_SIZE = 1000

  include PlatformHelper
  include ProjectsHelper
  include MemexesHelper
  include ConditionalAccessHelper

  IndexQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $first: Int!, $after: String, $query: String) {
      node(id: $projectOwnerId) {
        ...Views::Projects::Index::ProjectOwner
      }
    }
  GRAPHQL

  ListQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $first: Int!, $after: String, $query: String) {
      node(id: $projectOwnerId) {
        ...Views::Projects::List::ProjectOwner
      }
    }
  GRAPHQL

  def has_recently_visited_projects(owner)
    return false unless logged_in?
    return false unless owner.is_a?(Organization)
    return false unless GitHub.projects_new_enabled?
    owner.recently_visited_projects(viewer: current_user, cap_filter: cap_filter).any?
  end

  def projects_beta_count(owner)
    return 0 unless owner.is_a?(Organization)
    return 0 unless GitHub.projects_new_enabled?

    owner.accessible_memexes_scope(owner.memex_projects.open_projects, current_user).count
  end

  def repo_projects_beta_count(repo)
    return 0 unless GitHub.projects_new_enabled?

    memexes_ids = repo.memex_projects.map(&:id)
    scope = repo.owner.memex_projects.active_projects.where("id IN (?)", memexes_ids)
    repo.owner.accessible_memexes_scope(scope, current_user).count
  end

  def render_edit_project(owner:, project:)
    respond_to do |format|
      format.html do
        render "projects/edit", locals: {
          project: project,
        }
      end
    end
  end

  ShowQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $projectNumber: Int!, $maxColumns: Int!, $archivedStates: [ProjectCardArchivedState]!) {
      node(id: $projectOwnerId) {
        ...Views::Projects::Show::ProjectOwner
      }
    }
  GRAPHQL

  private def migrated_memex_path(project)
    project.project_migration.memex_project.url.to_s
  end

  private def redirect_to_migrated_memex?(project)
    project&.project_migration&.completed? && project.project_migration.memex_project&.readable_by?(current_user)
  end

  def render_show_project(owner:, project:, migration_notice_partial_path: nil)
    return redirect_to migrated_memex_path(project), status: :permanent_redirect if redirect_to_migrated_memex?(project)
    render_404
  end

  CreateProjectQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($ownerId: ID!, $name: String!, $body: String, $public: Boolean, $template: ProjectTemplate, $repositoryIds: [ID!]) {
      createProject(input: { ownerId: $ownerId, name: $name, body: $body, public: $public, template: $template, repositoryIds: $repositoryIds }) {
        project {
          resourcePath
        }
      }
    }
  GRAPHQL

  def update_project(owner:, project:)
    if project.update(project_params)
      project.notify_metadata_subscribers

      if request.xhr?
        render json: { project_name: project.name }
      else
        flash[:notice] = "Project updated"
        if params[:redirect_back].present?
          redirect_to :back
        else
          redirect_to project_path(project)
        end
      end
    else
      if request.xhr?
        render(json: { errors: project.errors.full_messages }, status: :unprocessable_entity)
      else
        flash.now[:error] = "Error saving your changes: #{project.errors.full_messages.to_sentence}"
        render "projects/edit", locals: { project: project }
      end
    end
  end

  def update_project_state(project:, state:, sync: nil)
    project.enqueue_resync_workflows if sync == "1"
    case state
    when "open"
      project.open if project.closed?
      flash[:notice] = "Project reopened."
    when "closed"
      project.close unless project.closed?
      flash[:notice] = "Project closed."
    end

    if params[:redirect_back].present?
      redirect_to :back
    else
      head :ok
    end
  end

  CloneProjectQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($targetOwnerId: ID!, $sourceId: ID!, $includeWorkflows: Boolean!, $name: String!, $body: String, $public: Boolean) {
      cloneProject(input: { targetOwnerId: $targetOwnerId, sourceId: $sourceId, includeWorkflows: $includeWorkflows, name: $name, body: $body, public: $public }) {
        project {
          resourcePath
        }
        jobStatusId
      }
    }
  GRAPHQL

  def clone_project(project:)
    variables = {
      targetOwnerId: project_clone_params[:global_target_owner_id],
      sourceId: project_clone_params[:global_source_id],
      includeWorkflows: project_clone_params[:include_workflows].to_i == 1,
      name: project_clone_params[:name],
      body: project_clone_params[:body],
    }

    if project_clone_params.has_key?(:public)
      variables[:public] = project_clone_params[:public].to_s == "true"
    end

    mutation = populate_flash_on_cap_error do
      platform_execute(CloneProjectQuery, variables: variables, context: { enforce_conditional_access_via_graphql: true })
    end
    return redirect_to project_path(this_project), status: :unauthorized if flash[:error].present?

    if mutation.errors.any?
      flash[:error] = "Uh oh! Something went wrong."
      redirect_to project_path(project)
    else
      GitHub.dogstats.increment("projects.created_with_template", tags: ["template:clone"])

      job_status_id = mutation.clone_project.job_status_id
      project = mutation.clone_project.project
      render json: { project_url: project.resource_path.to_s, job_status_url: job_status_url(job_status_id) }
    end
  end

  def migrate_project(project:, close_source_project:)
    return render_404 unless logged_in?

    if project.project_migration.present?
      # Soft delete the old memex project
      migrated_project = project.project_migration.memex_project
      migrated_project&.soft_delete!(current_user)

      # Delete current project migration
      project.project_migration.destroy
    end

    # For large enough projects, the validation step will timeout. For these cases, create
    # a migration without adding any specification so that the user can see a migration has started,
    # and queue job that will perform the validation and migration.
    if perform_migration_validation_async?(project)
      project_migration = ProjectMigration.new(requester: current_user, project: project)
      EnqueueLegacyProjectMigrationJob.perform_later(project.id, current_user.id)
      redirect_to :back
    else
      project_migration = MemexProject::Migrator.initialize!(current_user, project)

      if project_migration.save
        MigrateLegacyProjectJob.perform_later(project_migration.id)
        memex_project = project_migration.memex_project
        project_owner = memex_project.owner

        show_memex_path = project_owner.is_a?(Organization) ? show_org_memex_path(project_owner, memex_project.number) : show_user_memex_path(project_owner, memex_project.number)

        redirect_to show_memex_path
      else
        flash[:error] = "Migration failed. Please try again"
      end
    end

    GitHub.dogstats.increment("memex_project_migration.close_source_project", tags: ["close_source_project:#{close_source_project}"])
    if close_source_project == "true"
      project.close
    end
    project.notify_metadata_subscribers
  end

  DeleteProjectQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!) {
      deleteProject(input: { projectId: $projectId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def destroy_project(owner:)
    # platform_execute handles permissions checking for us but not flow control, so we're
    # still going to be using before_actions
    data = platform_execute(DeleteProjectQuery, variables: { "projectId" => params[:global_id] })

    if data.errors.all.any?
      # Checking the error type here is a temporary workaround. In the future,
      # platform_execute should be able to handle 404ing on a
      # NOT_FOUND by itself.
      if data.errors.details["deleteProject"].any? { |e| %w(NOT_FOUND UNAUTHENTICATED).include?(e["type"]) }
        render_404
      else
        project = typed_object_from_id([Platform::Objects::Project], params[:global_id])

        if project&.readable_by?(current_user)
          respond_to do |format|
            format.html do
              flash[:error] = "You don't have permission to delete this project. #{data.errors.messages.values.join(", ")}."
              redirect_to project_path(project)
            end

            format.json do
              head 403
            end
          end
        else
          render_404
        end
      end
    else
      redirect_to projects_path({ type: "classic" }, owner: owner)
    end
  end

  def render_project_search_results(owner:, project:)
    query = project.set_search_query_for(current_user, query: params[:q])
    respond_to do |format|
      format.html do
        pending_cards = pending_cards_for_search(project)
        search_results = search_result_cards(owner: owner, project: project, query: query, pending_cards: pending_cards)
        render partial: "projects/search_results", locals: {
          project: project,
          cards: search_results[:cards],
          is_initial_search: params[:more].blank?,
          next_page: search_results[:next_page],
          query: query,
          pending_cards_limited: project.cards.pending.count > ProjectCard::PENDING_LIMIT,
          pending_cards: pending_cards,
        }
      end
    end
  end

  def render_project_activity(owner:, project:)
    respond_to do |format|
      format.html do
        options = {
          viewer: current_user,
          page: params[:page] || 1,
          after: params[:after],
          latest_allowed_entry_time: params[:latest_allowed_entry_time],
        }
        render partial: "projects/activity/list", locals: {
          activities: Project::AuditLog.new(project, **options),
        }
      end
    end
  end

  AddCardsLinkQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectId: ID!) {
      node(id: $projectId) {
        ...Views::Projects::AddCardsLink::Project
      }
    }
  GRAPHQL

  def render_project_add_cards_link(project:)
    data = platform_execute(AddCardsLinkQuery, variables: { projectId: project.global_relay_id })

    respond_to do |format|
      format.html do
        render partial: "projects/add_cards_link", locals: { project: data.node }
      end
    end
  end

  def render_target_owner_results(project:)
    results = Project.query_valid_owners_for(viewer: current_user, query: params[:q])
    authorized_results = cap_filter.authorized_resources(results)

    sorted_results = authorized_results.sort_by do |target_owner|
      case target_owner
      when User
        [target_owner.display_login.downcase]
      when Repository
        [target_owner.owner.display_login.downcase, target_owner.name.downcase]
      end
    end

    current_owner = project.owner

    if sorted_results.include?(current_owner)
      sorted_results.delete(current_owner)
      sorted_results.unshift(current_owner)
      suggested_owner = current_owner
    else
      suggested_owner = nil
    end

    respond_to do |format|
      format.html_fragment { render partial: "projects/target_owner_results", formats: :html, locals: { results: sorted_results, suggested_owner: suggested_owner } }
    end
  end

  def render_linkable_repositories(owner:, project:)
    repos = ProjectRepositoryLink.linkable_repos_for(viewer: current_user, filter: params[:q], owner: owner)
    linked_repository_ids = project&.linked_repository_ids
    repos = repos.where.not(id: linked_repository_ids) if linked_repository_ids&.any?

    respond_to do |format|
      format.html_fragment do
        render partial: "projects/linkable_repositories", formats: :html,
          locals: {
            repositories: repos,
            project: project,
          }
      end
    end
  end

  private

  def deprecation_announcement_enabled?
    # Do not announce deprecation if creation is explicitly allowed for an environment (like GHES)
    !GitHub.projects_classic_creation_enabled?
  end

  def show_deprecation_announcement?(project, project_owner)
    return false unless project.writable_by?(current_user)
    deprecation_announcement_enabled?
  end

  def display_beta_migration_banner?(project, project_owner, notice:)
    return false unless project.writable_by?(current_user)
    return false if current_user.dismissed_project_notice?(notice, project_id: project.id)
    return false if deprecation_announcement_enabled?

    %w[
      Organization
      Repository
      User
    ].any? do |platform_type|
      project_owner.class.name.include?(platform_type)
    end
  end

  def perform_migration_validation_async?(project)
    project.cards.count > LARGE_MIGRATION_SIZE
  end

  def dismiss_project_notice(project:, project_owner:, notice:)
    return render_404 unless project

    current_user.dismiss_project_notice(notice, project_id: project.id)
    render_show_project(owner: project_owner, project: project)
  end

  def search_result_cards(owner:, project:, query:, pending_cards:)
    return unless logged_in?
    return unless project.writable_by?(current_user)

    parsed_issues_query = parse_issues_query(query, project)

    if owner.is_a?(User)
      has_repo_query = parsed_issues_query.group_by(&:first).keys.include?(:repo)
      unless has_repo_query
        parsed_issues_query = scope_query_to_linked_repos(parsed_issues_query, project)
      end

      parsed_issues_query = scope_query_to_user(parsed_issues_query, owner)
    end

    result_options = {
      per_page:     ProjectCard::PER_PAGE,
      page:         params[:page],
      query:        parsed_issues_query,
      current_user: current_user,
      remote_ip:    request.remote_ip,
      user_session: user_session,
      force_pulls:  false,
      prefill_associations: false, # We prefill below with only what we need
      tags: %W[controller:#{controller_name} action:#{action_name}],
      context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
    }

    result_options[:repo] = owner if owner.is_a?(Repository)

    result = Issue::SearchResult.search(**result_options)

    issues = result[:issues]
    issue_ids = issues.map(&:id)

    in_column_matches = project.cards.in_column.for_content_type("Issue").
      where(content_id: issue_ids).pluck(:content_id).
      index_by { |content_id| content_id }

    pending_cards_by_id = pending_cards.index_by(&:content_id)

    issues.delete_if do |issue|
      # Card is already in project.
      in_column_matches[issue.id] ||

      # Card is already shown in triage section.
      (params[:triage] && pending_cards_by_id[issue.id])
    end

    cards = issues.map do |issue|
      if pending_card = pending_cards_by_id[issue.id]
        pending_card
      else
        project.cards.build(content: issue, passed_redaction: true)
      end
    end

    cards = ProjectCardPrefiller.new(project, cards.compact, viewer: current_user).cards

    if owner.is_a?(User)
      # Ensure no issues not owned by the user/org are ever returned. The
      # search results may include issues from other users/orgs if -repo:
      # qualifiers are specified for every single repo owned by the user/org.
      cards.delete_if { |card| card.content.owner != owner }
    end

    { cards: cards, next_page: issues.next_page }
  end

  def project_params
    params.require(:project).permit(:name, :body, :track_progress, :public)
  end

  def linked_repository_ids_from_param(owner:)
    return unless owner.is_a?(User)

    params[:project_repository_link_ids]&.filter_map(&:presence)
  end

  def linked_repositories_from_param(owner:)
    repo_ids = linked_repository_ids_from_param(owner: owner)
    return Repository.none unless repo_ids&.any?

    repo_ids.map { |repo_id| typed_object_from_id([Platform::Objects::Repository], repo_id) }
  end

  def project_template_param
    return unless params[:project_template].present? && ProjectTemplate.valid?(params[:project_template])

    if params[:project_template] != ProjectTemplate::None.template_key
      params[:project_template]
    end
  end

  def project_clone_params
    params.require(:project).permit(:global_target_owner_id, :global_source_id, :include_workflows, :name, :body, :public)
  end

  def parse_issues_query(query, project)
    parsed_issues_query = Search::Queries::IssueQuery.normalize(
      Search::Queries::IssueQuery.parse(query),
    )

    if parsed_issues_query.exclude?([:no, "project"])
      parsed_issues_query << [:project, project.search_slug, true]
    end

    parsed_issues_query
  end

  # Scope query string to all linked repositories
  def scope_query_to_linked_repos(query, project)
    project.linked_repositories.each { |repo| query << [:repo, repo.name_with_display_owner] }
    query
  end

  # Adjust the query to only search repositories inside the user/organization
  def scope_query_to_user(query, user)
    contains_owned_repo = false
    array_parts, text_parts = query.partition { |term| term.is_a?(Array) }

    array_parts.delete_if do |key, value, negated|
      # Remove all org qualifiers from the query
      next true if key == :org

      if key == :repo
        owner, repo = value.split("/")

        # Remove all repositories without an owner
        next true if repo.blank?
        # Remove all repositories outside not owned by the user/org
        next true if owner.downcase != user.display_login.downcase

        contains_owned_repo = true unless negated
      end

      false
    end

    # Add org scope unless query targets a repo in the org
    unless contains_owned_repo
      key = user.organization? ? :org : :user
      array_parts << [key, user.display_login]
    end

    text_parts + array_parts
  end

  def project_index_query(add_sort_option = true)
    return @project_index_query if defined?(@project_index_query)
    query = parsed_projects_query.dup
    if !query.find { |(k, _v)| k == :sort } && add_sort_option
      query << [:sort, "created-desc"]
    end
    @project_index_query = Search::Queries::ProjectQuery.stringify(query)
  end

  def parsed_projects_query
    # Query params can come from projects land (:query) or the user profile (:q)
    # We have to support both here for search to work
    query = params[:query] || params[:q] || "is:open"

    Search::Queries::ProjectQuery.normalize(
      Search::Queries::ProjectQuery.parse(query),
    )
  end

  def pending_cards_for_search(project)
    pending_cards = project.cards.pending.order("created_at DESC").limit(ProjectCard::PENDING_LIMIT)
    pending_cards = ProjectCardRedactor.new(current_user, pending_cards).cards
    ProjectCardPrefiller.new(project, pending_cards, viewer: current_user).cards
  end

  def public_project_label
    "public"
  end

  def public_project_description
    if GitHub.enterprise?
      "Anyone with access to your GitHub Enterprise Server instance can see this project. You choose who can make changes."
    else
      "Anyone on the internet can see this project. You choose who can make changes."
    end
  end
end
