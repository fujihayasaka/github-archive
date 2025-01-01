# typed: false
# frozen_string_literal: true

class Actions::ActorsController < AbstractRepositoryController
  include ::ActionsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:index]

  param_encoding :index, :q, "ASCII-8BIT"

  def index
    actor_ids_filter = nil
    users = User.none
    search_query = params[:q].to_s
    ActiveRecord::Base.connected_to(role: :reading) do
      if current_repository.in_organization?
        actor_ids_filter = current_repository.organization.visible_users_for(current_user).pluck(:id)
      end
      ids = current_repository.user_ids_with_privileged_access(min_action: :write, actor_ids_filter: actor_ids_filter)
      users = User.where(id: ids).includes(:profile).by_login
    end
    is_lab = params[:lab] == "true"

    if search_query.present?
      users = users.select { |user| user.display_login.include?(search_query) }
    end

    respond_to do |format|
      format.any(:html, :html_fragment) do
        render "actions/actors/index",
          layout: false,
          formats: [:html, :html_fragment],
          locals: {
            selected_filename: params[:selected_filename],
            is_lab: is_lab,
            actors: users,
            selected_actor: workflow_run_filters[:actor],
            workflow_run_filters: workflow_run_filters
          }
      end

      format.json do
        render json: users.map { |user| { login: user.display_login, displayName: user.profile_name } }
      end
    end
  end
end
