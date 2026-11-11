# typed: true
# frozen_string_literal: true

class Orgs::People::FailedInvitationsController < Orgs::Controller
  include Orgs::Invitations::RateLimiting

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]
  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  before_action :login_required
  before_action :organization_admin_required
  before_action :sudo_filter, except: :index
  before_action :dotcom_required, only: :index

  javascript_bundle :organizations

  def index
    set_hovercard_subject(this_organization)

    view = create_view_model(
      Orgs::People::FailedInvitationsPageView,
      organization: this_organization,
      invitations: this_organization.active_failed_invitations,
      page: current_page,
      query: params[:query],
      rate_limited: org_invite_rate_limited?,
    )
    render "orgs/people/failed_invitations", locals: { view: view }
  end

  def update
    this_organization.retry_failed_invitations(current_user)
    flash[:notice] = "You've retried all failed invitations from #{this_organization.safe_profile_name}. It may take a few minutes to process."

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_back_or_to org_failed_invitations_path(this_organization)
    end
  end

  def destroy
    this_organization.destroy_failed_invitations(current_user)
    flash[:notice] = "You've deleted all failed invitations from #{this_organization.safe_profile_name}. It may take a few minutes to process."

    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_back_or_to org_failed_invitations_path(this_organization)
    end
  end
end
