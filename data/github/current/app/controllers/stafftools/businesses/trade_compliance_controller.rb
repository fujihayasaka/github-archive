# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::TradeComplianceController < Stafftools::Businesses::BusinessBaseController
  extend T::Sig

  before_action :business_required
  before_action :ensure_billing_enabled
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  sig { void }
  def show
    render "stafftools/businesses/trade_compliance/show", locals: { business: this_business, }
  end

  sig { void }
  def create
    this_business.trade_screening_record.instrument :view, actor: current_user, reason: "Billing info viewed by staff"
    render "stafftools/businesses/trade_compliance/show", locals: { business: this_business, show_billing_info: true, }
  end
end
