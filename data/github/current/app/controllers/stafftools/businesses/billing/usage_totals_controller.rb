# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::UsageTotalsController < Stafftools::Businesses::BillingController
  extend T::Sig

  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include ReactHelper

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
  only: [:show]

  before_action :ensure_vnext_enabled
  allow_verified_fetch only: [:show]

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  def show
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_business, **usage_filter_params)

        begin
          usage = Billing::Platform::Api::Client.new.get_usage_total(
            usage_entity_id: query[:usage_entity_id],
            product: query[:product].to_s,
            sku: query[:sku].to_s,
            billing_period: query[:billing_period],
            year: query[:year],
            month: query[:month],
            day: query[:day],
            hour: query[:hour],
          )
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
end
