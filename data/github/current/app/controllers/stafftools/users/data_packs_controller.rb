# typed: true
# frozen_string_literal: true

class Stafftools::Users::DataPacksController < Stafftools::UsersController

  def delete # rubocop:todo GitHub/UseRestfulActions
    this_user.reset_data_packs(actor: current_user)
    this_user.update_plan_with_data_packs

    flash[:notice] = "#{this_user.login}'s data subscription has been removed"
    redirect_to :back
  end
end
