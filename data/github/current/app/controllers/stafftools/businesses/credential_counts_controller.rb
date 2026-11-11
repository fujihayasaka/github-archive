# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::CredentialCountsController < Stafftools::Businesses::BusinessBaseController
  include Businesses::CredentialCountsHelper

  skip_before_action :dotcom_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Permissions,
    only: [:show]

  def show
    respond_to do |format|
      format.html do
        counts = fetch_credential_counts(this_business)
        render partial: "stafftools/businesses/credential_counts", locals: {
          business: this_business,
          counts: counts,
          timed_out: counts[:timed_out]
        }
      end
    end
  end
end
