# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CostCentersController < Stafftools::Businesses::BillingController

  include Businesses::Billing::CostCentersDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing, only: [:index, :show]

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def index
    state = params[:state] || "active"
    render_cost_centers_index(state: state)
  end

  sig { void }
  def show
    render_cost_center_show
  end

  # No filtering needed in Stafftools at the moment
  sig { override.params(cost_centers: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def filter_cost_centers(cost_centers) # rubocop:todo GitHub/UseRestfulActions
    cost_centers
  end
end
