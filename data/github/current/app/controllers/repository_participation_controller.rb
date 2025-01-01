# typed: true
# frozen_string_literal: true

class RepositoryParticipationController < ApplicationController
  before_action :ensure_repository_exists
  before_action :ensure_repository_permissions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    # Data not cached yet, so keep polling.
    unless data = GitHub::RepoGraph.participation_data(current_repository)
      return head 202
    end

    # Send svg graph response.
    respond_to do |format|
      format.html do
        if current_repository.empty?
          head 200
        else
          view = Repositories::ParticipationGraphView.new(
            data: data,
            width: params[:w].to_i,
            height: params[:h].to_i,
            repository: current_repository,
          )
          render partial: "repositories/participation_sparkline",
                locals: { view: view }
        end
      end
      format.json do
        render json: data.dig("all")
      end
    end
  rescue GitHub::RepoGraph::UnusableDataError
    head 204
  end

  private

  def ensure_repository_exists
    if !current_repository
      head 404
    end
  end

  def ensure_repository_permissions
    if !current_repository.pullable_by?(current_user)
      head 404
    end
  end

  def current_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_repository if defined?(@current_repository)
    @current_repository = this_user.repositories.where(name: params[:repository]).first if this_user
  end

  def this_user # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @user ||= User.find_by_login(params[:user_id])
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_user # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_user
  end
end
