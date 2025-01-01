# typed: true
# frozen_string_literal: true

class Hovercards::OrganizationProjectsController < ApplicationController
  include ProjectControllerActions

  before_action :require_xhr, only: :show
  before_action :require_organization, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:show]

  def show
    project = this_organization.visible_projects_for(current_user).find_by_number(params[:number].to_i)

    render_project_hovercard(project: project)
  end

  private

  def require_organization
    render_404 unless this_organization
  end

  memoize def this_organization
    Organization.find_by_login(params[:org]) if params[:org] && GitHub::UTF8.valid_unicode3?(params[:org])
  end

  def target_for_conditional_access
    this_organization || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def initialize_hydro_context
    super

    if hydro_context && hydro_context[:enabled] && this_organization
      hydro_context.merge!({
        current_org: this_organization.name,
        current_org_id: this_organization.id,
      })
    end
  end
end
