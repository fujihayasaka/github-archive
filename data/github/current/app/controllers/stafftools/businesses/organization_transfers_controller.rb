# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OrganizationTransfersController < Stafftools::Businesses::BusinessBaseController
  before_action :dotcom_required
  before_action :valid_direction_required, only: :index
  before_action :transfer_required, only: :update

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/businesses/organization_transfer_list", locals: {
      transfer_direction: direction,
      transfers: transfers,
    }
  end

  def create
    org = organization_from_param
    transfer = BusinessOrganizationTransfer.create \
      organization: org,
      from_business: org&.business,
      to_business: this_business,
      actor: current_user,
      site_admin_transfer: true
    if transfer.valid?
      BusinessOrganizationTransferJob.perform_later(transfer)
      flash[:notice] = "Organization transfer started. It may take a few minutes to complete."
    else
      flash[:error] = transfer.errors.full_messages.to_sentence
    end
    redirect_to stafftools_enterprise_organizations_path(this_business)
  end

  def update
    if params[:mark_as_failed] == "true"
      this_transfer.fail! reason: "Transfer marked as failed by GitHub staff"
      flash[:notice] = "Transfer marked as failed."
    end

    redirect_to :back
  end

  private

  def transfer_required
    render_404 unless this_transfer
  end

  memoize def this_transfer
    BusinessOrganizationTransfer.find_by(id: params[:id])
  end

  def valid_direction_required
    render_404 unless %w(initiated received).include?(direction)
  end

  def direction
    params[:direction].to_s
  end

  memoize def transfers
    scope = if direction == "initiated"
      BusinessOrganizationTransfer
        .includes(:organization, :from_business, :to_business, :actor)
        .where(from_business: this_business)
    elsif direction == "received"
      BusinessOrganizationTransfer
        .includes(:organization, :from_business, :to_business, :actor)
        .where(to_business: this_business)
    else
      BusinessOrganizationTransfer.none
    end
    scope.order(updated_at: :desc).paginate(page: current_page)
  end

  def organization_from_param
    ::Organization.find_by(login: params[:organization])
  end
end
