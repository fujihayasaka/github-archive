# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::Migrations::ActionsStorageBackfillController < Stafftools::Businesses::BillingController
  extend T::Sig

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  def create
    Billing::SharedStorage::BillingPlatformReplayFanoutJob.perform_later(business: this_business)
    flash[:notice] = "Enqueued job to backfill Actions storage"
    redirect_to stafftools_enterprise_billing_path(this_business)
  end
end
