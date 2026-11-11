# typed: true
# frozen_string_literal: true

class Stafftools::ActionInvocationController < StafftoolsController
  before_action :ensure_user_exists, only: [:block, :unblock]

  def block # rubocop:todo GitHub/UseRestfulActions
    Actions::Invocation.block(actor: this_user, staff_actor: current_user)
    flash[:notice] = "Action invocation blocked."
    redirect_to :back
  end

  def unblock # rubocop:todo GitHub/UseRestfulActions
    Actions::Invocation.unblock(actor: this_user, staff_actor: current_user)
    flash[:notice] = "Action invocation unblocked."
    redirect_to :back
  end
end
