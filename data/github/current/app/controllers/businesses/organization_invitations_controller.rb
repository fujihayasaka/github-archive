# typed: true
# frozen_string_literal: true

class Businesses::OrganizationInvitationsController < Businesses::BusinessController
  before_action :business_organization_invitations_required
  before_action :login_required
  before_action :business_owner_required, only: %i(index new create)
  before_action :sudo_filter, only: :create
  before_action :require_current_organization, only: :create
  before_action :non_idp_managed_business_required
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(index)

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot, only: [:new, :index], optional: true

  def index
    created_invitations = this_business
      .organization_invitations
      .with_status(:created)
      .reorder("business_organization_invitations.created_at asc")
    accepted_invitations = this_business
      .organization_invitations
      .with_status(:accepted)
      .reorder("business_organization_invitations.created_at asc")

    render "businesses/organizations/pending_organizations", locals: {
      created_invitations: created_invitations,
      accepted_invitations: accepted_invitations,
    }
  end

  def new
    render "businesses/organization_invitations/new"
  end

  def create
    begin
      this_business.invite_organization!(actor: current_user, organization: current_organization)
    rescue ActiveRecord::RecordInvalid => error
      flash[:error] = error.record.errors.full_messages.first
      return redirect_to :back
    rescue Business::CannotAddOrganizationError => error
      flash[:error] = error.message
      return redirect_to :back
    end

    if this_business.upgrade_initiated_from_organization == current_organization
      EnterpriseAccounts::KV.store.del(this_business.org_attachment_failure_notice_key(current_user))
    end

    flash[:notice] = <<~NOTICE.squish
      You've invited #{current_organization.display_login} organization to join #{this_business.name}!
      The organization's administrators will be receiving an email shortly.
      You can check the pending tab to manage the invitation.
    NOTICE
    redirect_to pending_organizations_enterprise_path(this_business)
  end

  private

  def require_current_organization
    return if current_organization.present?

    flash[:error] = "Could not find organization with login: #{params[:organization_login]}"
    redirect_to :back
  end

  def current_organization
    return unless params[:organization_login]
    @org ||= Organization.find_by(login: params.require(:organization_login))
  end
end
