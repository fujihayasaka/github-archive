# typed: strict
# frozen_string_literal: true

module Billing::RepoUsageDependency
  include Billing::Platform::Api::Utils
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_repo_usage_data(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)
        customer_id = this_entity.customer&.id
        params_customer_id = usage_filter_params[:customer_id]
        query[:cost_center_id] = ""

        # optionally pass in a list of organization IDs to filter usage for if the current user is org admin
        # this is only relevant for businesses on a non-stafftools route
        if !is_stafftools_route && this_entity.is_a?(Business)
          query[:organization_ids] = should_filter_for_org_admin?(this_entity, current_user) ? get_org_ids_for_org_admin(this_entity, current_user) : nil
        end

        usage = Billing::Platform::Api::Client.new.get_top_org_repo_usage_line_items(**T.unsafe(query))

        if usage.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occurred", usage: [] }, status: 500
        end

        render json: {
          usage: json_org_repo_billing_items(usage[:topUsages], query[:group_by]),
          other: json_other_billing_items(usage[:otherUsages])
        }, status: 200
      rescue => e # rubocop:todo Lint/GenericRescue
        Failbot.report(e)
        return render json: { error: "Unable to query repo usage", usage: [] }, status: 500
      end
    end
  end

  protected

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end
end
