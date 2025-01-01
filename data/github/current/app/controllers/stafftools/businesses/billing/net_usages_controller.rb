# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::NetUsagesController < Stafftools::Businesses::BillingController
  include Billing::Platform::Api::Utils
  include Customers::Billing::Concerns::NetUsages

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_business, **usage_filter_params)

        begin
          usage = Billing::Platform::Api::Client.new.get_net_usage_line_items(
            usage_entity_id: query[:usage_entity_id],
            product: query[:product].to_s,
            sku: query[:sku].to_s,
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            org_id: query[:org_id],
            repo_id: query[:repo_id],
            group_by: query[:group_by],
          )
        rescue => e # rubocop:todo Lint/GenericRescue
          Failbot.report(e)
          return render json: { error: "Unable to query usage", usage: [] }, status: 500
        end

        if usage.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occured", usage: [] }, status: 500
        end

        render json: { usage: json_billing_items(usage[:netUsageItems]) }, status: 200
      end
    end
  end

  private

  sig { override.returns(Business) }
  def this_entity
    this_business
  end
end
