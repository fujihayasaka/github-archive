# typed: strict
# frozen_string_literal: true

module Businesses::Billing::Concerns::UsageTotals
  include Billing::Platform::Api::Utils
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(this_entity: ::Billing::Types::Account).void }
  def render_usage_totals_data(this_entity:)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)

        begin
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
