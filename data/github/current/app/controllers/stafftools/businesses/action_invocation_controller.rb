# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ActionInvocationController < Stafftools::Businesses::BusinessBaseController
  def unblock # rubocop:todo GitHub/UseRestfulActions
    this_business.unblock_action_invocation(current_user)
    flash[:notice] = "Action invocation unblocked."
    redirect_to :back
  end
end
