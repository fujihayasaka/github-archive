# typed: strict
# frozen_string_literal: true

class Stafftools::Users::TradeComplianceController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :ensure_billing_enabled
  before_action :dotcom_required

  layout :overview_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    trade_controls_view = Stafftools::User::TradeControlsView.new(user: this_user)
    render "stafftools/users/trade_compliance/show", locals: { view: trade_controls_view }
  end

  sig { void }
  def create
    this_user.trade_screening_record.instrument :view, actor: current_user, reason: "Billing info viewed by staff"
    trade_controls_view = Stafftools::User::TradeControlsView.new(user: this_user, show_billing_info: true)
    render "stafftools/users/trade_compliance/show", locals: { view: trade_controls_view }
  end

  protected

  sig { returns(User) }
  def actor
    current_user
  end

  sig { returns(T.any(User, Organization)) }
  def target
    this_user
  end
end
