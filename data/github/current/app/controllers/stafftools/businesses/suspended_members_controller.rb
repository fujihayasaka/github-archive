# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SuspendedMembersController < Stafftools::Businesses::BusinessBaseController
  include BusinessesHelper

  skip_before_action :dotcom_required
  before_action :scim_managed_enterprise_required, only: %w(show)
  before_action :enterprise_managed_business_required, only: %w(destroy)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render "stafftools/businesses/suspended_members", locals: {
      suspended_members: this_business
        .suspended_members
        .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE),
    }
  end

  def destroy
    BusinessCleanupSuspendedUsersJob.perform_later(this_business, current_user)
    flash[:notice] = "Cleaning up inactive suspended user accounts in the background. This could take a few minutes."
    redirect_to stafftools_enterprise_path(this_business)
  end

  private

  def scim_managed_enterprise_required
    render_404 unless scim_managed_enterprise?(this_business)
  end
end
