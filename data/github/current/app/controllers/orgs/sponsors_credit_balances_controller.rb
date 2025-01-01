# typed: true
# frozen_string_literal: true

class Orgs::SponsorsCreditBalancesController < Orgs::Controller
  before_action :sponsors_required
  before_action :require_xhr
  before_action :login_required
  before_action :require_billing_manageable
  before_action :require_sponsors_customer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    credit_balance = this_sponsors_customer.credit_balance
    render "orgs/sponsors_credit_balances/show", locals: {
      credit_balance: credit_balance,
      organization: this_organization,
    }, layout: false
  rescue Zuorest::HttpError
    head(:unprocessable_entity)
  end

  private

  def require_billing_manageable
    render_404 unless org_billing_manageable?(this_organization)
  end

  memoize def this_sponsors_customer
    this_organization.sponsors_customer
  end

  def require_sponsors_customer
    head(:no_content) unless this_sponsors_customer
  end
end
