# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::RepoUsageController < Stafftools::Businesses::BillingController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency

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
    only: [:show]

  before_action :ensure_vnext_enabled
  allow_verified_fetch only: [:index]

  def show
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_business, **usage_filter_params)

        if this_business.feature_enabled?(:billing_org_repo_usage_refactor)
          businesss_customer_id = this_business.customer&.id
          params_customer_id = usage_filter_params[:customer_id]

          # if the input customer ID from the query is different from the current customer ID
          # then it is a cost center and we should pass it in as the cost center ID to the API
          if params_customer_id != businesss_customer_id.to_s
            query[:cost_center_id] = params_customer_id
            query[:usage_entity_id] = businesss_customer_id
          end

          usage = Billing::Platform::Api::Client.new.get_top_org_repo_usage_line_items(**T.unsafe(query))

          if usage.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occured", usage: [] }, status: 500
          end

          render json: {
            usage: json_org_repo_billing_items(usage[:topUsages], query[:group_by]),
            other: json_other_billing_items(usage[:otherUsages])
          }, status: 200
        else
          begin
            usage = Billing::Platform::Api::Client.new.get_repo_usage_line_items(
              usage_entity_id: query[:usage_entity_id],
              billing_period: query[:billing_period],
              year: query[:year],
              month: query[:month],
              day: query[:day],
              hour: query[:hour],
            )
          rescue => e # rubocop:todo Lint/GenericRescue
            Failbot.report(e)
            return render json: { error: "Unable to query repo usage", usage: [] }, status: 500
          end

          if usage.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occured", usage: [] }, status: 500
          end

          render json: { usage: json_org_repo_billing_items(usage[:repoUsages], query[:group_by]) }, status: 200
        end
      end
    end
  end
end
