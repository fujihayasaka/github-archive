# typed: true
# frozen_string_literal: true

class Biztools::RepositoryActions::ListingsController < BiztoolsController

  before_action :actions_required

  def destroy
    action = RepositoryAction.listed.find(params[:repository_action_id])

    action.delisted!

    redirect_to edit_biztools_repository_action_path(id: action.id),
      notice: "Okay, #{action.name} has been delisted."
  end

  private

  def actions_required
    render_404 unless GitHub.actions_enabled?
  end
end
