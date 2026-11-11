# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::BillingMismatchesController < Stafftools::SponsorsController
  skip_before_action :sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:unpaid_sponsorships]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :unpaid_sponsorships],
    optional: true

  INDEX_PER_PAGE = 10
  DEFAULT_DAY_WINDOW = 7

  def index
    render "stafftools/sponsors/billing_mismatches/index", locals: {
      days_ago: params[:days_ago],
      days_between: params[:days_between],
      sponsor_login: params[:sponsor_login],
    }
  end

  def unpaid_sponsorships # rubocop:todo GitHub/UseRestfulActions
    sponsor = if (sponsor_login = params[:sponsor_login]).present?
      User.find_by_login(sponsor_login)
    end

    sponsorships = Sponsorship.active.not_invoiced.unpaid
    sponsorships = sponsorships.from_sponsor(sponsor.id) if sponsor
    sponsorships = sponsorships.preload(
      :sponsor, :sponsorable, :tier,
      subscription_item: { plan_subscription: { customer: :payment_method } },
    ).order(id: :desc).paginate(page: current_page, per_page: INDEX_PER_PAGE)

    render "stafftools/sponsors/billing_mismatches/unpaid_sponsorships", locals: {
      sponsorships: sponsorships,
      sponsor_login: sponsor&.login,
      sponsorships_that_can_be_retried: sponsorships.select(&:can_retry_collecting_payment?),
    }, layout: !request.xhr? && !pjax?
  end
end
