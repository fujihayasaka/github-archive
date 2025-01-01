# typed: true
# frozen_string_literal: true

class Hovercards::RepositoryProjectsController < ApplicationController
  include ProjectControllerActions

  before_action :require_xhr, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    return render_404 unless repository

    project = repository.visible_projects_for(current_user).find_by_number(params[:number].to_i)

    render_project_hovercard(project: project)
  end

  private

  memoize def repository
    this_user.repositories.find_by_name(params[:repository]) if this_user
  end

  memoize def this_user
    if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
      User.find_by_login(params[:user_id])
    end
  end

  def target_for_conditional_access
    # Returning :no_target_for_conditional_access here is fine because we return 404 if trying to access
    # a repo that doesn't belong to this_user
    this_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def current_organization
    this_user if this_user.is_a?(Organization)
  end

  def initialize_hydro_context
    super

    return unless hydro_context && hydro_context[:enabled]

    if repository
      hydro_context.merge!({
        current_repo: repository.name_with_display_owner,
        current_repo_id: repository.id,
        current_repo_visibility: repository.public? ? :PUBLIC : :PRIVATE,
      })
    end

    if current_organization
      hydro_context.merge!({
        current_org: current_organization.name,
        current_org_id: current_organization.id,
      })
    end
  end
end
