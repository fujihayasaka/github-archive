# typed: true
# frozen_string_literal: true

class Businesses::NoticesController < Businesses::BusinessController
  before_action :login_required
  before_action -> do
    T.bind(self, Businesses::NoticesController)
    business_access_required(allow_members: true)
  end
  before_action :business_not_downgraded_to_free_plan_required
  skip_before_action :business_not_downgraded_to_free_plan_required, only: [:destroy]

  # Dismiss a notice
  def destroy
    notice = params.require(:notice)
    current_user.dismiss_business_notice(notice, business_id: this_business.id)
    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  # Reset/undismiss a notice
  def update
    notice = params.require(:notice)
    current_user.reset_business_notice(notice, business_id: this_business.id)

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end
end
