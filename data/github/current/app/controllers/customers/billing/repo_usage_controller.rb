# typed: true
# frozen_string_literal: true

class Customers::Billing::RepoUsageController < Customers::BillingController
  include Billing::Platform::Api::Utils

  depends_on_clusters ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      only: [:show]

  def show
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **repo_usage_filter_params)
        usage_response = Billing::Platform::Api::Client.new.get_usage_line_items(**T.unsafe(query))

        if usage_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occured", usage: [] }, status: 500
        end

        usage = usage_response[:repoUsages]

        if this_entity.is_a?(Business)
          usage = filter_repo_usage_by_ownership(usages: usage, current_user: current_user, business: this_entity)
        end

        render json: { usage: json_org_repo_billing_items(usage, query[:group_by]) }, status: 200
      rescue => e # rubocop:todo Lint/GenericRescue
        Failbot.report(e)
        return render json: { error: "Unable to query repo usage", usage: [] }, status: 500
      end
    end
  end

  private

  def repo_usage_filter_params
    usage_filter_params.except(:group)
  end
end
