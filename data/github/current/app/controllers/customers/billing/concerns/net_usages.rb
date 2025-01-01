# typed: strict
# frozen_string_literal: true

module Customers::Billing::Concerns::NetUsages
  include Billing::Platform::Api::Utils

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { abstract.returns(::Billing::Types::Account) }
  def this_entity; end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_net_usages(this_entity:, is_stafftools_route: false)
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
            group_by: 5,
          }

          id = cost_center_id(new_query)
          if !id.nil?
            new_query[:cost_center_id] = id
          end

          usage_response = Billing::Platform::Api::Client.new.get_net_usage_line_items(**new_query)
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end

          usage = filter_usage_by_query(usages: usage_response[:netUsageItems], query: query)
        else
          usage_response = Billing::Platform::Api::Client.new.get_net_usage_line_items(**T.unsafe(query))
          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred" }, status: 500
          end
          usage = usage_response[:netUsageItems]
        end

        # don't filter if this is a stafftools route
        usages =
          if !is_stafftools_route
            filter_repo_usage_by_ownership(usages: usage, current_user: current_user, entity: this_entity)
          else
            usage
          end
        render json: { usage: json_billing_items(usages) }, status: 200
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        render json: { error: "Unable to query usage", usage: [] }, status: 500
      end
    end
  end

  private

  sig { params(billing_items: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[String]) }
  def json_billing_items(billing_items)
    return [] if billing_items.nil?
    billing_items.map { |item| Billing::Platform::Api::NetUsageLineItem.new(item, org_or_repo_request: org_or_repo_request?(query)).to_json }
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
    "All"
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
