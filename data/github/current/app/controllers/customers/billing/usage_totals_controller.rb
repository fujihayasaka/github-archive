# typed: strict
# frozen_string_literal: true

class Customers::Billing::UsageTotalsController < Customers::BillingController
  depends_on_clusters ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)
        new_query = {
          usage_entity_id: query[:usage_entity_id],
          product: query[:product],
          sku: query[:sku],
          billing_period: query[:billing_period],
          year: query[:year],
          month: query[:month],
          day: query[:day],
          hour: query[:hour],
        }
        usage = Billing::Platform::Api::Client.new.get_usage_total(**new_query)

        if usage.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occured", usage: nil }, status: 500
        end

        render json: { usage: usage }, status: 200
      rescue => e # rubocop:todo Lint/GenericRescue
        return render json: { error: "Unable to query usage", usage: nil }, status: 500
      end
    end
  end
end
