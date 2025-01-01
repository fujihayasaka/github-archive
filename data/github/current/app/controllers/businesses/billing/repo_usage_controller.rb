# typed: true
# frozen_string_literal: true

class Businesses::Billing::RepoUsageController < Businesses::BillingsController
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
    only: [:show]

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

          # optionally pass in a list of organization IDs to filter usage for if the current user is org admin
          query[:organization_ids] = should_filter_for_org_admin? ? get_org_ids_for_org_admin : nil

          usage = Billing::Platform::Api::Client.new.get_top_org_repo_usage_line_items(**T.unsafe(query))

          if usage.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occured", usage: [] }, status: 500
          end

          render json: {
            usage: json_org_repo_billing_items(usage[:topUsages], query[:group_by]),
            other: json_other_billing_items(usage[:otherUsages])
          }, status: 200
        else
          usage = Billing::Platform::Api::Client.new.get_usage_line_items(**T.unsafe(query))

          if usage.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occured", usage: [] }, status: 500
          end

          usages = filter_repo_usage_by_ownership(usages: usage[:billingItems], current_user: current_user, business: this_business)
          render json: { usage: json_org_repo_billing_items(usages, query[:group_by]) }, status: 200
        end
      rescue => e # rubocop:todo Lint/GenericRescue
        Failbot.report(e)
        return render json: { error: "Unable to query repo usage", usage: [] }, status: 500
      end
    end
  end

  private

  sig { returns(T::Boolean) }
  def should_filter_for_org_admin?
    # do not filter billing manager or business owner usage
    !this_business.billing_manager?(current_user) && !this_business.owner?(current_user)
  end

  sig { returns(T::Array[Integer]) }
  def get_org_ids_for_org_admin
    current_user&.owned_organization_ids & this_business.organization_ids
  end
end
