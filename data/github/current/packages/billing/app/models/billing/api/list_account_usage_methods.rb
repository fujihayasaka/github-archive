# typed: true
# frozen_string_literal: true

module Billing
  module Api
    module ListAccountUsageMethods
      extend T::Helpers

      module Methods
        extend T::Sig

        sig { returns(T::Boolean) }
        def has_error?
          T.unsafe(self).is_a?(Billing::Api::ClientWrapper::BillingClientError)
        end

        sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
        def total_codespaces_usage_by_owner
          return if has_error?

          T.unsafe(self)[:account_usage].map do |account_usage|
            {
              owner_id: account_usage[:account][:account_id],
              owner_type: account_usage[:account][:account_type],
            }.merge(total_codespaces_usage(account_usage[:product_usage]))
          end
        end

        sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
        def total_copilot_usage_by_owner
          return if has_error?

          T.unsafe(self)[:account_usage].map do |account_usage|
            {
              owner_id: account_usage[:account][:account_id],
              owner_type: account_usage[:account][:account_type],
            }.merge(total_copilot_usage(account_usage[:product_usage]))
          end
        end

        private

        sig { params(product_usage: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Hash[Symbol, T.untyped]) }
        def total_codespaces_usage(product_usage)
          compute_usage = product_usage.select do |product_usage|
            product_usage[:product_sku][:name].include?("compute")
          end

          storage_usage = product_usage.select do |product_usage|
            product_usage[:product_sku][:name].include?("storage")
          end

          {
            compute_effective_quantity: (compute_usage.sum { |product_usage| product_usage[:usage][:effective_quantity] }).round(2),
            storage_effective_quantity: (storage_usage.sum { |product_usage| product_usage[:usage][:effective_quantity] }).round(2),
            cost_in_subunits: product_usage.sum { |product_usage| product_usage[:usage][:estimated_cost][:subunits] }
          }
        end

        sig { params(product_usage: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Hash[Symbol, T.untyped]) }
        def total_copilot_usage(product_usage)
          copilot_for_business = product_usage.select do |product_usage|
            product_usage[:product][:name].include?("copilot")
          end

          {
            effective_quantity: (copilot_for_business.sum { |product_usage| product_usage[:usage][:effective_quantity] }).round(4),
            cost_in_subunits: copilot_for_business.sum { |product_usage| product_usage[:usage][:estimated_cost][:subunits] }
          }
        end
      end

      include Methods

      mixes_in_class_methods(Methods)
    end
  end
end
