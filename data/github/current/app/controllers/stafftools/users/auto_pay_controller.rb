# typed: strict
# frozen_string_literal: true

class Stafftools::Users::AutoPayController < Stafftools::Users::BillingController
  include Billing::AutoPayActions

  before_action :ensure_billing_record_exists

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Stafftools::Users::AutoPayController#create",
    "Stafftools::Users::AutoPayController#destroy",
  ].freeze, T::Array[String])

  private

  sig { returns(T.untyped) }
  def billable_account
    this_user
  end

  sig { returns(String) }
  def billing_information_path
    stafftools_user_billing_information_index_path(this_user)
  end
end
