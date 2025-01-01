# typed: strict
# frozen_string_literal: true

class Businesses::Billing::UsageTableController < Businesses::BillingsController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:index]

  sig { void }
  def index
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_business, **usage_filter_params)

        group_by = query[:group_by]
        is_group_by_org_or_repo = org_or_repo_request?(query)
        is_filter_by_org_or_repo = query[:org_id].present? || query[:repo_id].present?

        if is_group_by_org_or_repo && !is_filter_by_org_or_repo
          query[:organization_ids] = should_filter_for_org_admin?(this_business, current_user) ? get_org_ids_for_org_admin(this_business, current_user) : nil

          business_customer_id = this_business.customer&.id
          params_customer_id = usage_filter_params[:customer_id]

          # if the input customer ID from the query is different from the current customer ID
          # then it is a cost center and we should pass it in as the cost center ID to the API
          if params_customer_id != business_customer_id.to_s
            query[:cost_center_id] = params_customer_id
            query[:usage_entity_id] = business_customer_id
          end
        end

        if query[:cost_center_id].nil? || query[:cost_center_id] == ""
          query[:cost_center_id] = "All"
        end

        # filter out usage for organization admins
        if !this_business.billing_manager?(current_user) && !this_business.owner?(current_user)
          if is_group_by_org_or_repo && !is_filter_by_org_or_repo
            usage_response = billing_platform_client.get_paginated_usage_line_items(**T.unsafe(query))
          else
            # force group by to be org/repo/product/sku for organization admins to allow us to filter out usage
            # for orgs they don't have access to
            usage_response = billing_platform_client.get_net_usage_line_items(
              **T.unsafe(query),
              group_by: BillingPlatform::Base::UsageGroupBy::GroupByOrgRepoProductSku,
            )
          end

          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end

          if is_group_by_org_or_repo && !is_filter_by_org_or_repo
            usage = filter_usage_by_query(usages: usage_response[:orgRepoItems], query: query)
          else
            usage = filter_usage_by_query(usages: usage_response[:netUsageItems], query: query)
          end
        else
          if is_group_by_org_or_repo && !is_filter_by_org_or_repo
            usage_response = billing_platform_client.get_paginated_usage_line_items(**T.unsafe(query))
          else
            usage_response = billing_platform_client.get_net_usage_line_items(**T.unsafe(query))
          end

          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occured", usage: [] }, status: 500
          end

          if is_group_by_org_or_repo && !is_filter_by_org_or_repo
            usage = usage_response[:orgRepoItems]
          else
            usage = usage_response[:netUsageItems]
          end
        end

        total_line_items_count = usage_response[:totalLineItemsCount]

        usages = filter_repo_usage_by_ownership(usages: usage, current_user: current_user, entity: this_business)

        if is_group_by_org_or_repo
          response = {}

          if is_filter_by_org_or_repo
            response[:usage] = json_billing_items(usages, org_or_repo_request: org_or_repo_request?(query))
          else
            response[:usage] = json_org_repo_billing_items(usages, group_by)
          end

          if !is_filter_by_org_or_repo
            response[:totalLineItemsCount] = total_line_items_count
          end

          render json: response, status: 200
        else
          render json: { usage: json_billing_items(usages, org_or_repo_request: org_or_repo_request?(query)) }, status: 200
        end
      end
    end
  end
end
