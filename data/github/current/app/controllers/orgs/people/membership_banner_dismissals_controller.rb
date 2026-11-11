# typed: true
# frozen_string_literal: true

class Orgs::People::MembershipBannerDismissalsController < Orgs::Controller
  before_action :login_required

  def create
    current_user.dismiss_notice("org_membership_banner")

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end
end
