# typed: true
# frozen_string_literal: true

class Orgs::MemexProjectLinksController < Orgs::Controller
  include Memexes::ProjectLinkDependency

  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings

  def create
    projects_changes = params.to_unsafe_h.with_indifferent_access[:projects_changes].presence || {}
    # We only want to update the links for active MemexProjects which have an accompanying active MemexTemplate record
    memex_project_numbers = current_organization.memex_projects.active_projects.templates.where(number: projects_changes.keys).pluck(:number)
    update_links_params = projects_changes.select do |memex_project_number, _changes|
      memex_project_numbers.include?(memex_project_number.to_i)
    end

    update_project_links(
      update_links_params: update_links_params,
      context: current_organization,
      redirect_path: settings_org_projects_path(current_organization),
      publish_add_event: method(:publish_organization_memex_project_link_add),
      publish_remove_event: method(:publish_organization_memex_project_link_remove)
    )
  end

  def reorder # rubocop:todo GitHub/UseRestfulActions
    memex_project_links = params[:memex_project_links].presence || []
    query = current_organization.memex_project_links.where(id: memex_project_links).in_order_of(:id, memex_project_links)
    query.each_with_index do |memex_project_link, index|
      memex_project_link.update!(position: index)
    end

    head :ok
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:show]

  def show
    project_suggester = ProjectSuggester.new(
      viewer: current_user,
      context: current_organization,
      load_memex_projects: true,
      only_memex_templates: true,
      load_classic_projects: false,
    )
    recommended_memex_project_ids = current_organization.memex_project_links.pluck(:memex_project_id)
    suggested_organization_projects = project_suggester.organization_projects(min_permission_level: "read")
    # We want to render the already selected projects first, then the rest of the suggested projects in the suggested order
    first_results, remaining_results = suggested_organization_projects.partition do |memex_project|
      recommended_memex_project_ids.include?(memex_project.id)
    end
    recommendable_memex_projects = first_results + remaining_results
    remaining_recommended_memex_projects_count = MemexTemplate::MAX_ORGANIZATION_RECOMMENDED_TEMPLATES - recommended_memex_project_ids.length

    respond_to do |format|
      format.html do
        render("orgs/memex_project_links/show",
          layout: false,
          format: [:html],
          locals: {
            recommendable_memex_projects: recommendable_memex_projects,
            recommended_memex_project_ids: recommended_memex_project_ids,
            remaining_recommended_memex_projects_count: remaining_recommended_memex_projects_count,
          }
        )
      end
    end
  end

  private

  def ensure_current_organization
    render_404 unless current_organization
  end

  def publish_organization_memex_project_link_add(memex:)
    publish_memex_event(name: "organization_link_template_add", memex: memex)
  end

  def publish_organization_memex_project_link_remove(memex:)
    publish_memex_event(name: "organization_link_template_remove", memex: memex)
  end

  def publish_memex_event(name:, memex: nil)
    GlobalInstrumenter.instrument("memex_event",
      {
        actor: current_user,
        memex_project: memex,
        memex_project_column: nil,
        memex_project_item: nil,
        name: name,
        ui: nil,
        context: "",
        memex_project_view: nil,
        repository: nil,
      }
    )
  end
end
