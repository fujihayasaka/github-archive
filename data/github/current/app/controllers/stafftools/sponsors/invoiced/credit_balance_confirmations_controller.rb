# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::CreditBalanceConfirmationsController < StafftoolsController
  before_action :sponsors_required
  before_action :require_invoiced_sponsor

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render("stafftools/sponsors/invoiced/credit_balance_confirmations/show",
      locals: {
        sponsor: sponsor,
        amount: amount,
        comment: comment,
        reference_id: reference_id,
      }
    )
  end

  private

  memoize def sponsor
    User.find_by_login(params[:invoiced_sponsor_id])
  end

  def amount
    params[:amount]
  end

  def comment
    params[:comment]
  end

  def reference_id
    params[:reference_id]
  end

  def require_invoiced_sponsor
    render_404 unless sponsor&.sponsors_invoiced?
  end
end
