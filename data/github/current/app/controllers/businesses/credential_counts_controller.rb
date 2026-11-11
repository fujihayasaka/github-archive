# typed: true
# frozen_string_literal: true

class Businesses::CredentialCountsController < Businesses::BusinessController
  include Businesses::CredentialCountsHelper

  before_action :business_owner_required, if: :enterprise_managed_business?
  before_action :read_enterprise_sso_required, unless: :enterprise_managed_business?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Permissions,
    only: [:show]

  def show
    respond_to do |format|
      format.html do
        counts = fetch_credential_counts(this_business)
        render partial: "businesses/settings/security/credential_counts", locals: {
          this_business: this_business,
          counts: counts,
          timed_out: counts[:timed_out]
        }
      end
    end
  end

  private

  def enterprise_managed_business?
    this_business&.enterprise_managed_user_enabled?
  end
end
