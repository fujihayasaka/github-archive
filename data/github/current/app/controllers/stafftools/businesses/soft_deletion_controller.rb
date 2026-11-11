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
    end

    redirect_to stafftools_enterprises_path
  end
end
