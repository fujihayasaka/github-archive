# typed: true
# frozen_string_literal: true

class Orgs::DisplayedNoticesController < ApplicationController
  include OrganizationsHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :org_members_only
  after_action :customer_category_instrumentation

  # Allow requests from React apps using the verifiedFetch function
  allow_verified_fetch only: [:destroy]

  def destroy
    input = params.require(:input).permit(:organizationId, :notice, :forWholeOrg)
    org = Organization.find_by(id: input[:organizationId])
    for_whole_org = input[:forWholeOrg].present?
    return respond_with_404 unless notice_dismissable?(org)

    # TODO - Remove the below logic once notices_dependency has been updated (https://github.com/github/octogrowth/issues/1282)
    if current_user.dismissed_organization_notice?(input[:notice], org)
      current_user.reset_organization_notice(input[:notice], org)
    end

    current_user.dismiss_organization_notice(input[:notice], org, for_whole_org: for_whole_org)

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  private

  def respond_with_404
    request.xhr? ? head(404) : render_404
  end

  def notice_dismissable?(org)
    org&.member?(current_user) || org&.adminable_by?(current_user)
  end
end
