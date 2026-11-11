# typed: true
# frozen_string_literal: true

class Stafftools::Users::Successors::PromotionsController < StafftoolsController
  before_action :ensure_user_exists
  before_action :dotcom_required

  def create
    if this_user.mark_deceased
      flash[:notice] = "#{this_user.login} marked as deceased"
    else
      flash[:error] = this_user.errors.full_messages.to_sentence
    end

    redirect_to stafftools_user_path(this_user)
  end
end
