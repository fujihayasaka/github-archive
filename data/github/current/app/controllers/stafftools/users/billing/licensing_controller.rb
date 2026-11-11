# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::LicensingController < Stafftools::Users::BillingController
  T.unsafe(self).react_bundle_name = "billing-app"

  include Billing::Platform::Api::Utils

  before_action :ensure_user_exists
  before_action :ensure_vnext_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    only: [:index]

  sig { void }
  def index
    view = BillingSettings::OverviewView.new(account: this_user, current_user: current_user, target: this_user)

    render "stafftools/users/licensing/show",
           layout: "stafftools/organization/billing",
           locals: {
             this_user: this_user,
             target: this_user,
             is_stafftools_route: true,
             view: view,
             is_trial_expired: false
           }
  end
end
