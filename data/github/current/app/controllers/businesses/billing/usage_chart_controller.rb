# typed: strict
# frozen_string_literal: true

class Businesses::Billing::UsageChartController < Businesses::BillingsController
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

        usages = {}
        group_by = BillingPlatform::Base::UsageGroupBy::NoGroupBy
        if this_business&.feature_enabled?(:usage_chart_api)
          new_query = {
            usage_entity_id: query[:usage_entity_id],
            product: query[:product],
            sku: query[:sku],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            billing_period: query[:billing_period],
            org_id: query[:org_id],
            repo_id: query[:repo_id],
            group_by: query[:group_by],
            cost_center_id: query[:cost_center_id],
            filtered_orgs: query[:filtered_orgs],
            filtered_repos: query[:filtered_repos]
          }

          begin
            usage_response = Billing::Platform::Api::Client.new.get_usage_chart_data(**new_query)
          rescue => e # rubocop:todo Lint/GenericRescue
            Failbot.report(e, app: "billing-platform")
            return render json: { error: "Unable to query usage", usage: [] }, status: 500
          end

          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred", usage: [] }, status: 500
          end

          usages = usage_response

          if !query[:group_by].nil?
            group_by = query[:group_by]
          end
        end

        render json: { usage: json_billing_items(usages, group_by) }, status: 200
      end
    end
  end

  private

  sig { params(billing_items: T::Hash[Symbol, T::Array[T.untyped]], group_by: Integer).returns(T.nilable(T::Array[T.untyped])) }
  def json_billing_items(billing_items, group_by)
    return [] if billing_items.blank?

    billing_items[:usageChartData]&.map do |d|
      { name: get_usage_name(d[:name], group_by), data: d[:data] }
    end
  end

  sig { params(name: String, group_by: Integer).returns(String) }
  def get_usage_name(name, group_by)
    if group_by == BillingPlatform::Base::UsageGroupBy::GroupByOrganization
      # Grouped by org
      org = Organization.find_by(id: name)
      name = org.nil? ? name : org.display_login
    elsif group_by == BillingPlatform::Base::UsageGroupBy::GroupByRepository
      # Grouped by repo
      repo = Repository.find_by(id: name)
      name = repo.nil? ? name : repo.name_with_display_owner
    end
    name
  end
end
