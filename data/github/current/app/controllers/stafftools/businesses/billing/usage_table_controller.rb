# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsageTableController < Stafftools::Businesses::BillingController
  include Billing::Platform::Api::Utils
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: [:index]

  sig { void }
  def index
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_business, **usage_filter_params)
        usage_response = billing_platform_client.get_net_usage_line_items(**T.unsafe(query))

        if usage_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occured", usage: [] }, status: 500
        end

        usage = usage_response[:netUsageItems]

        group_by = query[:group_by]
        if group_by == BillingPlatform::Base::UsageGroupBy::GroupByRepository || group_by == BillingPlatform::Base::UsageGroupBy::GroupByOrganization
          render json: { usage: json_org_repo_billing_items(usage, group_by) }, status: 200
        else
          render json: { usage: json_billing_items(usage, org_or_repo_request: org_or_repo_request?(query)) }, status: 200
        end
      end
    end
  end
end
