# typed: strict
# frozen_string_literal: true

class Businesses::Billing::ContactsController < Businesses::BillingsController
  before_action :business_access_required

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
    only: [:index]

  sig { void }
  def index
    render "businesses/billing_platform/contacts", locals: { business: this_business }
  end
end
