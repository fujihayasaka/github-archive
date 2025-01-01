# typed: strict
# frozen_string_literal: true

module Billing::UsageChartDependency
  include Billing::Platform::Api::Utils
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_usage_chart_data(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)

        usages = {}
        group_by = BillingPlatform::Base::UsageGroupBy::NoGroupBy
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
          filtered_orgs: filtered_orgs(is_stafftools_route: is_stafftools_route, this_entity: this_entity),
        }

        begin
          usage_response = billing_platform_client.get_usage_chart_data(**new_query)
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

        render json: { usage: json_billing_items(usages, group_by) }, status: 200
      end
    end
  end

  protected

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

  sig { params(is_stafftools_route: T::Boolean, this_entity: ::Billing::Types::Account).returns(T.nilable(T::Array[String])) }
  def filtered_orgs(is_stafftools_route:, this_entity:)
    if is_stafftools_route
      # Don't filter out any data for stafftools routes
      return nil
    end
    # Only business requests will need to filter data by a specific org
    if should_filter_usage_for_business?(this_entity, current_user)
      if this_entity.is_a?(Business)
        get_org_ids_for_org_admin(this_entity, current_user).map(&:to_s)
      else
        nil
      end
    end
  end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end

  sig { abstract.returns(Billing::Platform::Api::Client) }
  def billing_platform_client; end

end
