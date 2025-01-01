# typed: strict
# frozen_string_literal: true

module Customers::Billing::Concerns::NetUsages
  include Billing::Platform::Api::Utils

  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { abstract.returns(Business) }
  def this_business; end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end

  sig { void }
  def render_net_usages
    respond_to do |format|
      format.json do
        if !this_business.billing_manager?(current_user) && !this_business.owner?(current_user)
          new_query = {
            usage_entity_id: query[:usage_entity_id].to_s,
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
            group_by: 5,
          }

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

        usages = filter_repo_usage_by_ownership(usages: usage, current_user: current_user, business: this_business)
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
    Billing::Public::Usage::QueryBuilder.build(this_business, **usage_filter_params)
  end
end
