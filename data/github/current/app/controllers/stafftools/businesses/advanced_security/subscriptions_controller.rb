# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::AdvancedSecurity::SubscriptionsController < Stafftools::Businesses::BusinessBaseController

  sig { void }
  def update
    operation_id = params[:operation_id]
    case operation_id
    when "cancel"
      result = this_business.cancel_advanced_security_subscription(
        actor: current_user,
        force: true,
      )
      if result.ok?
        flash[:notice] = "Cancelled Advanced Security subscription."
      else
        flash[:error] = "Failed to cancel Advanced Security subscription: #{result.error.message}"
      end
      redirect_to stafftools_enterprise_path(this_business)
    else
      render_404
    end
  end
end
