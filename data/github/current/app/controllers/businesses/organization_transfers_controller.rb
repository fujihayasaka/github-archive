# typed: true
# frozen_string_literal: true

class Businesses::OrganizationTransfersController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required
  before_action :member_organization_required, only: %w(new create)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:new]

  def new
    org = Organization.find_by(id: params[:organization_id])
    transfer = BusinessOrganizationTransfer.new \
      from_business: this_business, organization: org
    render "businesses/organization_transfers/new", locals: { transfer: transfer }
  end

  def create
    transfer = BusinessOrganizationTransfer.create \
      organization: organization,
      from_business: this_business,
      to_business: to_business,
      actor: current_user

    begin
      to_business.ensure_sufficient_licenses_for_organization!(organization) if organization.present?
    rescue Business::CannotAddOrganizationError => e
      redirect_to :back, flash: { error: e.message }
      return
    end

    if transfer.valid?
      BusinessOrganizationTransferJob.perform_later(transfer)
      redirect_to enterprise_organizations_path(this_business),
        notice: "Organization transfer started. It may take a few minutes to complete."
    else
      redirect_to :back, flash: { error: transfer.errors.full_messages.to_sentence }
    end
  end

  private

  def member_organization_required
    render_404 unless organization
  end

  def organization # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @organization if defined?(@organization)

    org = Organization.find_by(id: params[:organization_id])
    @organization = if org.present? && Business.from_org_id(org.id) == this_business
      org
    else
      nil
    end
  end

  def to_business
    Business.find(params[:to_business_id])
  end
end
