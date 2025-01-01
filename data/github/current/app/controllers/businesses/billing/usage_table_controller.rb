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

        # filter out usage for organization admins
        if !this_business.billing_manager?(current_user) && !this_business.owner?(current_user)
          # force group by to be org/repo/product/sku for organization admins to allow us to filter out usage
          # for orgs they don't have access to
          usage_response = billing_platform_client.get_net_usage_line_items(
            **T.unsafe(query),
            group_by: BillingPlatform::Base::UsageGroupBy::GroupByOrgRepoProductSku,
          )
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end

          usage = filter_usage_by_query(usages: usage_response[:netUsageItems], query: query)
        else
          usage_response = billing_platform_client.get_net_usage_line_items(**T.unsafe(query))
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occured", usage: [] }, status: 500
          end

          usage = usage_response[:netUsageItems]
        end

        usages = filter_repo_usage_by_ownership(usages: usage, current_user: current_user, business: this_business)

        group_by = query[:group_by]
        if group_by == BillingPlatform::Base::UsageGroupBy::GroupByRepository || group_by == BillingPlatform::Base::UsageGroupBy::GroupByOrganization
          render json: { usage: json_org_repo_billing_items(usages, group_by) }, status: 200
        else
          render json: { usage: json_billing_items(usages, org_or_repo_request: org_or_repo_request?(query)) }, status: 200
        end
      end
    end
  end
end
