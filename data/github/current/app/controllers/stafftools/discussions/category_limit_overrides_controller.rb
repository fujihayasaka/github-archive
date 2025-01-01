# typed: true
# frozen_string_literal: true

class Stafftools::Discussions::CategoryLimitOverridesController < StafftoolsController
  include DiscussionsStafftoolsRoutesHelper

  before_action :ensure_repo_exists

  def update
    result = limit_override.set(limit: params[:limit].to_i)

    if result.success?
      flash[:notice] = "Successfully updated category limit to #{params[:limit]}"
    else
      flash[:error] = "Failed updating category limit: #{result.errors.to_sentence}"
    end

    redirect_to gh_stafftools_repository_discussions_path(current_repository)
  end

  def destroy
    result = limit_override.delete

    if result.success?
      flash[:notice] = "Successfully removed category limit override"
    else
      flash[:error] = "Failed removing category limit override: #{result.errors.to_sentence}"
    end

    redirect_to gh_stafftools_repository_discussions_path(current_repository)
  end

  private

  memoize def limit_override
    DiscussionCategory::LimitOverride.new(repository: current_repository, actor: current_user)
  end
end
