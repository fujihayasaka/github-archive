# typed: true
# frozen_string_literal: true

module Billing
  class CreateProductForBillingCycleJob < ApplicationJob
    retry_on StandardError

    queue_as :zuora

    def perform(params)
      with_write do
        zuora_product = ::GitHub::Billing::ZuoraProduct.new(
          charges: params[:charges],
          product_name: params[:product_name],
          product_type: params[:product_type],
          product_key: params[:product_key],
          custom_product_params: params[:custom_product_params]
        )
        zuora_product.create_product_for_billing_cycle(params[:billing_cycle], params[:product_id])
      end
    end
  end
end
