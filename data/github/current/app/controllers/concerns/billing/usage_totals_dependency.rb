# typed: strict
# frozen_string_literal: true

module Billing::UsageTotalsDependency
  include Billing::Platform::Api::Utils
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_usage_totals_data(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)

        begin
          if this_entity.is_a?(Business)
            new_query = {
              customer_id: query[:usage_entity_id],
              year: query[:year],
              month: query[:month],
              organization_admin_ids: !is_stafftools_route && should_filter_for_org_admin?(this_entity, current_user) ? get_org_ids_for_org_admin(this_entity, current_user) : nil
            }
            usage = Billing::Platform::Api::Client.new.get_enterprise_usage_totals(**new_query)
          else
            new_query = {
              usage_entity_id: query[:usage_entity_id],
              product: query[:product],
              sku: query[:sku],
              billing_period: query[:billing_period],
              year: query[:year],
              month: query[:month],
              day: query[:day],
              hour: query[:hour],
            }
            usage = Billing::Platform::Api::Client.new.get_usage_total(**new_query)
          end
        rescue => e # rubocop:todo Lint/GenericRescue
          Failbot.report(e)
          return render json: { error: "Unable to query usage", usage: nil }, status: 500
        end

        if usage.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occured", usage: nil }, status: 500
        end

        render json: { usage: usage }, status: 200
      end
    end
  end

  protected

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end
end
