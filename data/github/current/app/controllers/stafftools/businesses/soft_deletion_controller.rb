# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SoftDeletionController < Stafftools::Businesses::BusinessBaseController
  include Stafftools::Businesses::TradeCompliance::SharedControllerMethods

  before_action do
    T.bind(self, Stafftools::Businesses::SoftDeletionController)
    ensure_target_not_restricted(return_to: stafftools_enterprises_path)
  end

  def create
    begin
      this_business.soft_delete!(actor: current_user)
      flash[:notice] = "Deleted #{this_business.name}."
    rescue Business::SoftDeletionUnsupportedError
      if this_business.enterprise_managed_user_enabled? && !current_user.feature_enabled?(:emu_ea_deletion)
        flash[:error] = "Could not delete '#{this_business.name}' because it is an externally managed enterprise."
      elsif this_business.organizations_blocking_deletion? && !(current_user.feature_enabled?(:soft_delete_organization) || this_business.feature_enabled?(:soft_delete_organization))
        flash[:error] = "All organizations must removed or transferred before the enterprise can be deleted."
      end
    end

    redirect_to stafftools_enterprises_path
  end
end
