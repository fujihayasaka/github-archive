# typed: true
# frozen_string_literal: true

class Businesses::SecurityController < Businesses::BusinessController
  include BusinessesHelper

  before_action :business_owner_required

  # Allow pagination above the cap of 100 for customers with 1000s
  # of ip allow list entries
  skip_before_action :cap_pagination, only: %i(index)

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
    only: [:index]

  def index
    respond_to do |format|
      format.html do
        if request.xhr? && GitHub.ip_allowlists_available?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "ip_allowlist_entries/list", locals: {
            owner: this_business,
            new_entry_path: enterprise_ip_allowlist_entries_path(this_business)
          }
        else
          render "businesses/settings/security", locals: {
            params: params_for_saml_test_result
          }
        end
      end
    end
  end
end
