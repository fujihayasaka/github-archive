# typed: true
# frozen_string_literal: true

class PinnedEnvironmentsController < AbstractRepositoryController
  before_action :login_required
  before_action :write_access_required

  def create
    if environment(params[:environment]).pin(actor: current_user)
      flash[:notice] = "The environment has been pinned."
    else
      flash[:error] = "The environment could not be pinned."
    end
    redirect_to :back
  end

  def destroy
    if environment(params[:environment]).unpin(actor: current_user)
      flash[:notice] = "The environment has been unpinned."
    else
      flash[:error] = "The environment could not be unpinned."
    end
    redirect_to :back
  end

  private

  def environment(name)
    @environment ||= Environment.where(repository_id: current_repository.id, name: name).first
  end

  def write_access_required
    render_404 unless current_repository.can_pin_environments?(current_user)
  end
end
