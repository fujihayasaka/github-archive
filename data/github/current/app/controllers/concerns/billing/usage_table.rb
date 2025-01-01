# typed: strict
# frozen_string_literal: true

module Billing::UsageTable
  include Billing::Platform::Api::Utils
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_usage_table_data(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)
        query[:organization_ids] = (should_filter_for_org_admin?(this_entity, current_user) && !is_stafftools_route) ? get_org_ids_for_org_admin(this_entity, current_user) : nil

        is_group_by_org_or_repo = org_or_repo_request?(query)
        is_filter_by_org_or_repo = query[:org_id].present? || query[:repo_id].present?

        if query[:cost_center_id].nil? || query[:cost_center_id] == ""
          query[:cost_center_id] = ""
        end

        if is_group_by_org_or_repo && !is_filter_by_org_or_repo
          usage_response = billing_platform_client.get_top_org_repo_usage_line_items(**T.unsafe(query), include_discounts: true)

          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred", usage: [] }, status: 500
          end

          usage = usage_response
        else
          usage_response = billing_platform_client.get_net_usage_line_items(**T.unsafe(query))

          if usage_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "An unknown error occurred", usage: [] }, status: 500
          end

          usage = usage_response[:netUsageItems]
        end

        if is_group_by_org_or_repo
          response = {}

          if is_filter_by_org_or_repo
            response[:usage] = json_billing_items(usage)
          else
            response[:usage] = json_org_repo_billing_items(usage[:topUsages], query[:group_by])
            response[:other] = json_other_billing_items(usage[:otherUsages])
          end

          render json: response, status: 200
        else
          render json: { usage: json_billing_items(usage) }, status: 200
        end
      end
    end
  end

  protected

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end

  sig { abstract.returns(Billing::Platform::Api::Client) }
  def billing_platform_client; end
end
