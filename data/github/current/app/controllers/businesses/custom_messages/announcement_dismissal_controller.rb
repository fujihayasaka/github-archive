# typed: true
# frozen_string_literal: true

class Businesses::CustomMessages::AnnouncementDismissalController < Businesses::BusinessController
  include CustomMessagesHelper

  before_action :enterprise_required
  before_action :login_required

  def create
    error = current_user.dismiss_global_enterprise_announcement(uuid: params[:uuid])

    if error
      head :not_found
    elsif request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end
end
