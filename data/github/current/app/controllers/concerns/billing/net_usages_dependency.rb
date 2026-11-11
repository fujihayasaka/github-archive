# typed: strict
# frozen_string_literal: true

module Billing::NetUsagesDependency
  include Billing::Platform::Api::Utils

  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  abstract!

  sig { abstract.returns(::Billing::Types::Account) }
  def this_entity; end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end

  sig { params(this_entity: ::Billing::Types::Account, current_user: T.nilable(User), is_stafftools_route: T::Boolean).void }
  def render_net_usages(this_entity:, current_user:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        if !can_query_all_usage?(this_entity: this_entity, is_stafftools_route: is_stafftools_route)
          new_query = {
            usage_entity_id: query[:usage_entity_id].to_s,
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            group_by: query[:group_by],
          }

          # filter out usage for organization admins
          if this_entity.is_a?(Business)
            new_query[:organization_ids] = get_org_ids_for_org_admin(this_entity, current_user)
          end

          id = cost_center_id(new_query)
          if !id.nil?
            new_query[:cost_center_id] = id
          end

          usage_response = Billing::Platform::Api::Client.new.get_net_usage_line_items(
            usage_entity_id: new_query[:usage_entity_id],
            product: new_query[:product],
            sku: new_query[:sku],
            billing_period: new_query[:billing_period],
            year: new_query[:year],
            month: new_query[:month],
            day: new_query[:day],
            hour: new_query[:hour],
            org_id: new_query[:org_id],
            repo_id: new_query[:repo_id],
            group_by: new_query[:group_by],
            cost_center_id: new_query[:cost_center_id],
            organization_ids: new_query[:organization_ids]
          )
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end

          usage = filter_usage_by_query(usages: usage_response[:netUsageItems], query: query)
        else
          usage_response = usage_response = Billing::Platform::Api::Client.new.get_net_usage_line_items(
            usage_entity_id: query[:usage_entity_id],
            product: query[:product],
            sku: query[:sku],
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            org_id: query[:org_id],
            repo_id: query[:repo_id],
            group_by: query[:group_by],
            cost_center_id: query[:cost_center_id],
            organization_ids: query[:organization_ids]
          )
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end
          usage = usage_response[:netUsageItems]
        end

        render json: { usage: json_billing_items(usage) }, status: 200
      rescue StandardError => e # rubocop:todo Lint/RescueException
        render json: { error: "Unable to query usage", usage: [] }, status: 500
      end
    end
  end

  private

  sig { params(billing_items: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[String]) }
  def json_billing_items(billing_items)
    return [] if billing_items.nil?
    billing_items.map { |item| Billing::Platform::Api::NetUsageLineItem.new(item).to_json }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def query
    query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)
    id = cost_center_id(query)
    if !id.nil?
      query[:cost_center_id] = id
    end
    query
  end

  sig { params(query: T::Hash[Symbol, T.untyped]).returns(T.nilable(String)) }
  def cost_center_id(query)
    if !query[:cost_center_id].nil?
      return query[:cost_center_id]
    end
    ""
  end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).returns(T::Boolean) }
  def can_query_all_usage?(this_entity:, is_stafftools_route:)
    return true if is_stafftools_route
    if this_entity.is_a?(Business) && !this_entity.billing_manager?(current_user) && !this_entity.owner?(current_user)
      return false
    elsif this_entity.is_a?(Organization) && !org_admin_or_billing_manager?(entity: this_entity, current_user: current_user)
      return false
    end
    true
  end
end
