# typed: strict
# frozen_string_literal: true

class Orgs::Settings::PaymentHistoryController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :dotcom_required

  PER_PAGE = 10

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  sig { void }
  def index
    if this_organization.billed_via_billing_platform?
      payment_records = Billing::Settings::PaymentHistory::PaymentRecord.payment_records(target: this_organization)
      payment_records = payment_records.paginate(
        page: current_page,
        per_page: PER_PAGE
      )

      render "orgs/settings/payment_history/index", locals: {
        target: this_organization,
        payment_records: payment_records,
      }
    else
      render_404
    end
  end
end
