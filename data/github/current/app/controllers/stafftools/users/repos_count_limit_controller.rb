# typed: true
# frozen_string_literal: true

class Stafftools::Users::ReposCountLimitController < StafftoolsController
  before_action :ensure_user_exists

  def create
    limiter = RepositoryLimit.new(this_user)
    new_soft_limit = params[:repo_soft_limit_override]&.to_i || limiter.soft_limit
    new_hard_limit = params[:repo_hard_limit_override]&.to_i || limiter.hard_limit
    limiter.override(soft: new_soft_limit, hard: new_hard_limit)
  rescue ArgumentError => error
    flash[:error] = error.message
  ensure
    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  def destroy
    limiter = RepositoryLimit.new(this_user)
    limiter.reset_override

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end
end
