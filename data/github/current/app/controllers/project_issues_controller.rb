# typed: true
# frozen_string_literal: true

class ProjectIssuesController < AbstractRepositoryController

  include Issues::RateLimitsDependency
  include IssuesHelper

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
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:projects_suggestions]

  # Matches only strings that are project search slugs. Examples:
  # project:github/github/1 - match
  # project:github/1        - match
  # -project:github/1       - no match
  # no:project:github/1     - no match
  PROJECT_PARAM_SELECTOR = %r{(\s|^)project:(#{ProjectQueryParam::SHORTHAND})}.freeze

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

  def new
    issue = current_repository.issues.build

    project_ids = issue_project_ids(params.to_unsafe_h).each_with_object([]) do |(project_id, should_add), result|
      result << project_id if should_add == "on"
    end
    projects = issue.potential_projects_for(current_user, ids: project_ids)
    issue.project_ids = projects.map(&:id)

    memex_projects = []
    if GitHub.projects_new_enabled?
      memex_project_ids = issue_memex_project_ids(params.to_unsafe_h).each_with_object([]) do |(memex_project_id, should_add), result|
        result << memex_project_id if should_add == "on"
      end
      memex_projects = issue.potential_memex_projects_for(current_user, ids: memex_project_ids)
      issue.memex_project_ids = memex_projects.map(&:id)
    end

    respond_to do |format|
      format.html do
        render partial: "issues/sidebar/new/projects",
               locals: { issue: issue, projects: projects + memex_projects, deferred_content: false }
      end
    end
  end

  def update
    issue_params = update_params
    project_ids = issue_project_ids issue_params

    issue = current_repository.issues.find_by_number(issue_params[:issue_number])
    old_issue_project_ids = issue.project_ids
    issue_project_ids_to_remove = []
    projects = issue.potential_projects_for(current_user, ids: project_ids.keys)

    projects.each do |project|
      if project_ids[project.id.to_s] == "on"
        next if old_issue_project_ids.include?(project.id)
        card = project.cards.build(creator: current_user)
        card.set_content_from(actor: current_user, params: { content_type: "Issue", content_id: issue.id })
        card.save!
      else
        issue_project_ids_to_remove << project.id
      end
    end

    if issue_project_ids_to_remove.any?
      ProjectCard.where(project_id: issue_project_ids_to_remove).for_content(issue).destroy_all
    end

    memex_projects = []
    errors = []

    if GitHub.projects_new_enabled?
      issue_or_pull = issue.pull_request? ? issue.pull_request : issue

      memex_project_ids = issue_memex_project_ids issue_params
      memex_projects = issue.potential_memex_projects_for(current_user, ids: memex_project_ids.keys).to_a
      memex_project_ids_to_remove = []

      memex_projects.each do |memex_project|
        if memex_project_ids[memex_project.id.to_s] == "on"
          item = memex_project.build_item(creator: current_user, issue_or_pull: issue_or_pull)
          if item.valid?
            memex_project.save_with_priority!(item)
          elsif item.errors.any?
            errors << item.errors.first.full_message
          end
        else
          memex_project_ids_to_remove << memex_project.id
        end
      end

      if memex_project_ids_to_remove.any?
        MemexProjectItem.where(memex_project_id: memex_project_ids_to_remove).where(content: issue_or_pull).destroy_all
      end
    end

    track_issue_edits_from_project_board(edited_fields: ["projects"])
    error_message = errors.first if errors.any?

    respond_to do |format|
      format.html do
        render partial: "issues/sidebar/show/projects",
               locals: { issue: issue, projects: projects + memex_projects, error_message: error_message, inline: params[:inline] }
      end
    end
  end

  def projects_suggestions # rubocop:todo GitHub/UseRestfulActions
    scope = params.require(:scope)

    projects_access_level = if params.has_key?(:access_level)
      params[:access_level]
    else
      GitHub.logger.info(
        "Missing param: access_level",
        {
          "code.namespace": "ProjectIssuesController",
          "code.function": "projects_suggestions",
          "gh.issues.params": params
        }
      )
      "write"
    end

    suggester = ProjectSuggester.new(
      viewer: current_user,
      context: current_repository,
      load_memex_projects: GitHub.projects_new_enabled?,
      load_classic_projects: params[:load_classic_projects] == "false" ? false : ProjectsClassicSunset.projects_classic_ui_enabled?(current_user, org: current_repository.organization)
    )

    owner = current_repository.owner

    projects = if scope == "recent"
      suggester.recent_projects(
        min_permission_level: projects_access_level,
        include_repo_linked: true
      )
    elsif scope == "repository" && current_repository.projects_enabled?
      suggester.repository_projects(min_permission_level: projects_access_level)
    elsif scope == "organization" && owner.organization? && owner.organization_projects_enabled?
      suggester.organization_projects(min_permission_level: projects_access_level)
    elsif scope == "user" && owner.user?
      suggester.user_projects(min_permission_level: projects_access_level)
    end

    return render status: 404, json: { message: "Scope #{scope} not found" } if projects.nil?

    selected_project_ids, selected_memex_project_ids = [], []

    if params.has_key?(:issue_number)
      current_issue = current_repository.issues.find_by_number(params[:issue_number])
      return render status: 404, json: { message: "Issue #{params[:issue_number]} not found" } if current_issue.nil?
      selected_project_ids, selected_memex_project_ids = get_selected_project_ids_for_issue(current_issue)
    elsif params.has_key?(:search_query)
      selected_project_ids, selected_memex_project_ids = get_selected_project_ids_for_query(params[:search_query], projects)
    end

    projects_hash = hash_projects(projects, selected_project_ids, selected_memex_project_ids)

    expires_in 5.seconds, public: false
    render json: {
      projects: projects_hash.sort_by! { |p| p[:selected] ? 0 : 1 }
    }
  end

  # This overrides the service catalog tagging defined in `service_mapping` to modify the catalog service tagging to properly associate to pull requests.
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    issue_or_pull_request = params.has_key?(:issue_number) && current_repository ? current_repository.issues.find_by_number(params[:issue_number]) : nil
    if issue_or_pull_request && issue_or_pull_request.pull_request?
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/#{PULL_REQUESTS_TAG}"
    else
      super
    end
  end

  private

  def get_selected_project_ids_for_query(search_query, projects)
    return [], [] unless search_query.include?("project:")

    project_ids = []
    memex_project_ids = []

    search_query.gsub(PROJECT_PARAM_SELECTOR) do
      match = T.must(Regexp.last_match)
      project_shorthand = T.must(match[:shorthand]).downcase
      parts = project_shorthand.split("/")

      selected_project = projects.find { |p| p.search_slug.downcase == project_shorthand }
      next unless selected_project.present?

      if selected_project.is_a?(Project) && ProjectsClassicSunset.projects_classic_ui_enabled?(current_user, org: current_repository.organization)
        project_ids.push(selected_project.id)
      else
        memex_project_ids.push(selected_project.id)
      end
    end

    [project_ids, memex_project_ids]
  end

  def get_selected_project_ids_for_issue(current_issue)
    issue_or_pull = current_issue.pull_request? ? current_issue.pull_request : current_issue
    selected_project_ids = ProjectsClassicSunset.projects_classic_ui_enabled?(current_user, org: current_repository.organization) ? current_issue.project_ids : []
    selected_memex_project_ids = issue_or_pull.memex_project_ids

    # Fallback if selected_memex_project_ids is not set when blank
    if !selected_memex_project_ids.present? && current_issue.new_record?
      selected_memex_project_ids = issue_or_pull.memex_project_items.map(&:memex_project_id).uniq
    end

    # Fallback to issue.cards for new records since project_ids won't be set
    if !selected_project_ids.present? && current_issue.new_record?
      selected_project_ids = current_issue.cards.map(&:project_id).uniq
    end

    [selected_project_ids, selected_memex_project_ids]
  end

  def update_params
    params.to_unsafe_h.with_indifferent_access.slice :issue_project_ids, :issue_memex_project_ids, :issue_number
  end

  def issue_project_ids(parameters)
    ids = parameters[:issue_project_ids]
    return ids if ids.is_a?(Hash)

    {}
  end

  def issue_memex_project_ids(parameters)
    ids = parameters[:issue_memex_project_ids]
    return ids if ids.is_a?(Hash)

    {}
  end

  def hash_key_for_project(p)
    "#{p.is_a?(Project) ? "project" : "memex_project"}_#{p.id}"
  end

  def project_id_for_hash_key(key)
    # key is a compound of a project type (memex_project, project) and id
    key.split("_").last.to_i
  end

  def hash_projects(projects, selected_project_ids, selected_memex_project_ids)
    # Prepare each MemexProject's memex_template association for use within project_suggestion_hash_with_lookup
    memex_projects = projects.select { |p| p.is_a?(MemexProject) }
    GitHub::PrefillAssociations.prefill_batch_method(memex_projects, :is_template?)
    projects.map { |p| project_suggestion_hash_with_lookup(p, selected_project_ids, selected_memex_project_ids) }
  end

  def project_suggestion_hash_with_lookup(project, selected_project_ids, selected_memex_project_ids)
    owner = if project.owner_type == "Organization"
      project.owner.safe_profile_name
    elsif project.owner_type == "Repository"
      project.owner.name_with_display_owner
    elsif project.owner_type == "User"
      project.owner.display_login
    end

    {
      id: project.id,
      name: project.name,
      owner: owner,
      type: project.is_a?(Project) ? "project" : "memex_project",
      template: project.is_a?(MemexProject) ? project.is_template? : false,
      selected: project.is_a?(Project) ? selected_project_ids.include?(project.id) : selected_memex_project_ids.include?(project.id),
      search_slug: project.search_slug,
    }
  end
end
