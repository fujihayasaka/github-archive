# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::InformationController < Stafftools::Businesses::BillingController
  include Stafftools::Billing::Information::SharedControllerMethods

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Stafftools::Businesses::Billing::InformationController#create",
  ].freeze, T::Array[String])

  sig { void }
  def index
    render "stafftools/businesses/billing/information/index"
  end

  private

  sig { override.params(params: T::Hash[String, String]).void }
  def redirect_to_information_path(params)
    redirect_to stafftools_enterprise_billing_information_index_path(this_business, **params)
  end
end
