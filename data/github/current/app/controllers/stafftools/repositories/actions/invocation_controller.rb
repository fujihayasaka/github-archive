# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::InvocationController < StafftoolsController
  before_action :ensure_repo_exists

  def create
    # Note this bypasses Actions::Invocation and will not emit
    # the actions.invocation_unblocked event
    current_repository.unblock_action_invocation(current_user)
    flash[:notice] = "Action invocation unblocked."
    redirect_to :back
  end

  def destroy
    # Note this bypasses Actions::Invocation and will not emit
    # the actions.invocation_blocked event
    current_repository.block_action_invocation(current_user)
    flash[:notice] = "Action invocation blocked."
    redirect_to :back
  end
end
