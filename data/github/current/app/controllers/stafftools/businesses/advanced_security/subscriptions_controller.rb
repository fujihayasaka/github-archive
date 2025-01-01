# typed: strict
# frozen_string_literal: true
class Stafftools::Businesses::AdvancedSecurity::SubscriptionsController < Stafftools::Businesses::BusinessBaseController
  extend T::Sig

  before_action :not_found_if_emu

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

  private

  sig { void }
  def not_found_if_emu
    render_404 if this_business&.enterprise_managed_user_enabled?
  end
end
