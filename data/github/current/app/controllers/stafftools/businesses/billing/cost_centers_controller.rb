# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CostCentersController < Stafftools::Businesses::BillingController

  include Businesses::Billing::CostCentersDependency

  # Cached cost center response - not used in stafftools but required by the concern
  sig { override.returns(T.nilable(T.any(T::Hash[Symbol, T.untyped], Billing::Platform::Api::Error))) }
  attr_accessor :cached_cost_center_response

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
    add_client_feature_flag([:billing_cost_centers_ui_pagination_enabled], entity: this_business)
    state = params[:state] || "active"

    if FeatureFlag.vexi.enabled?(:billing_cost_centers_ui_pagination_enabled, this_business, default: false)
      page = params[:page].to_i > 0 ? params[:page].to_i : 1
      render_cost_centers_index(state: state, page: page)
    else
      render_cost_centers_index(state: state)
    end
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
