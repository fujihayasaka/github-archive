# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::GitLfsUsageController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: %i(show)

  def show
    respond_to do |format|
      format.html do
        render "stafftools/businesses/git_lfs_usage",
          locals: { business: this_business },
          layout: false
      end
    end
  end
end
