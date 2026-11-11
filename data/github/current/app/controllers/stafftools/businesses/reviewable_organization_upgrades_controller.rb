# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ReviewableOrganizationUpgradesController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :business_required, only: %i(index)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(index)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    render "stafftools/businesses/organization_upgrades_list", layout: "stafftools", locals: {
      pending_completion_upgrades: Business
        .upgraded_and_not_reviewed
        .includes(:upgraded_from)
        .order("upgraded_at DESC")
        .paginate(page: current_page(:pending_page), per_page: DEFAULT_PAGE_SIZE),
      completed_upgrades: Business
        .upgraded_and_reviewed
        .includes(:upgraded_from, :upgrade_reviewed_by)
        .order("upgrade_reviewed_at DESC")
        .paginate(page: current_page(:reviewed_page), per_page: DEFAULT_PAGE_SIZE)
    }
  end

  def update
    begin
      if this_business.review_upgrade(current_user)
        flash[:notice] = "Marked this organization to enterprise upgrade as reviewed."
      else
        flash[:error] = "Sorry, this organization to enterprise upgrade review couldn't be completed."
      end
    rescue Business::AlreadyReviewedUpgradeError
      flash[:error] = "This organization to enterprise upgrade has already been reviewed."
    end

    redirect_to organization_upgrades_stafftools_enterprises_path
  end
end
