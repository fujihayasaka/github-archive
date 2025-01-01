# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::ZuoraWebhooksController < Stafftools::Businesses::BillingController
  include Stafftools::Billing::Concerns::ZuoraWebhooksMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    customers = [this_business.customer]
    show_zuora_webhooks(customers)
  end
end
