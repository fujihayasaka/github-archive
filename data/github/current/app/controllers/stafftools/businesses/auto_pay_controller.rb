# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::AutoPayController < Stafftools::Businesses::BusinessBaseController
  include Stafftools::BillingPermissionCheck
  include Billing::AutoPayActions

  before_action :ensure_billing_enabled
  before_action :ensure_billing_record_exists

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Stafftools::Businesses::AutoPayController#create",
    "Stafftools::Businesses::AutoPayController#destroy",
  ].freeze, T::Array[String])

  private

  sig { returns(T.untyped) }
  def billable_account
    this_business
  end

  sig { returns(String) }
  def billing_information_path
    stafftools_enterprise_billing_information_index_path(this_business)
  end
end
