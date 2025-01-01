# typed: true
# frozen_string_literal: true

class Hovercards::UserProjectsController < ApplicationController
  include ProjectControllerActions

  before_action :require_xhr, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show]

  def show
    return render_404 unless this_user

    project = this_user.visible_projects_for(current_user).find_by_number(params[:number].to_i)

    render_project_hovercard(project: project)
  end

  private

  memoize def this_user
    if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
      User.find_by_login(params[:user_id])
    end
  end

  def target_for_conditional_access
    this_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
