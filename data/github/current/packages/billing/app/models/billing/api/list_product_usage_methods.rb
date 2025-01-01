# typed: strict
# frozen_string_literal: true

module Billing
  module Api
    module ListProductUsageMethods
      extend T::Helpers

      module Methods
        extend T::Sig
        sig { returns(T::Boolean) }
        def has_error?
          T.bind(self, Object)

          self.is_a?(Billing::Api::ClientWrapper::BillingClientError)
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def meuse_product_usage
          return if has_error?
          T.bind(self, T::Hash[Symbol, T.untyped])

          self[:product_usage].sum { |product_usage| product_usage[:usage][:effective_quantity] }.round(4)
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def meuse_product_cost
          return if has_error?
          T.bind(self, T::Hash[Symbol, T.untyped])

          self[:product_usage].sum { |product_usage| product_usage[:usage][:estimated_cost][:subunits] }
        end

        sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
        def compute_usage
          return if has_error?
          T.bind(self, T::Hash[Symbol, T.untyped])

          self[:product_usage].select do |product_usage|
            product_usage[:product_sku][:name].include?("compute")
          end
        end

        sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
        def storage_usage
          return if has_error?
          T.bind(self, T::Hash[Symbol, T.untyped])

          self[:product_usage].select do |product_usage|
            product_usage[:product_sku][:name].include?("storage")
          end
        end

        sig { params(sku: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def compute_usage_by_sku(sku)
          return if has_error?

          T.must(compute_usage).find do |product_usage|
            product_usage[:product_sku][:name].eql?(sku)
          end
        end

        sig { params(sku: String).returns(T.nilable(::Billing::Types::Numeric)) }
        def compute_total_usage_by_sku(sku)
          return if has_error?

          sku_usage = compute_usage_by_sku(sku)
          if sku_usage
            (sku_usage[:usage][:quantity]).round(2)
          else
            0
          end
        end

        sig { params(sku: String).returns(T.nilable(::Billing::Types::Numeric)) }
        def compute_effective_usage_by_sku(sku)
          return if has_error?
          sku_usage = compute_usage_by_sku(sku)
          if sku_usage
            (sku_usage[:usage][:effective_quantity]).round(2)
          else
            0
          end
        end

        sig { params(sku: String).returns(T.nilable(::Billing::Types::Numeric)) }
        def compute_total_cost_by_sku(sku)
          return if has_error?
          sku_usage = compute_usage_by_sku(sku)
          if sku_usage
            sku_usage[:usage][:estimated_cost][:subunits]
          else
            0
          end
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def compute_total_usage
          return if has_error?
          (T.must(compute_usage).map { |product_usage| product_usage[:usage][:quantity] }.reduce(:+) || 0).round(2)
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def storage_total_usage
          return if has_error?
          (T.must(storage_usage).map { |product_usage| product_usage[:usage][:quantity] }.reduce(:+) || 0).round(2)
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def compute_effective_usage
          return if has_error?
          (T.must(compute_usage).map { |product_usage| product_usage[:usage][:effective_quantity] }.reduce(:+) || 0).round(2)
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def storage_effective_usage
          return if has_error?
          (T.must(storage_usage).map { |product_usage| product_usage[:usage][:effective_quantity] }.reduce(:+) || 0).round(2)
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def compute_total_cost_in_subunits
          return if has_error?
          T.must(compute_usage).map { |product_usage| product_usage[:usage][:estimated_cost][:subunits] }.reduce(:+) || 0
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def storage_total_cost_in_subunits
          return if has_error?
          T.must(storage_usage).map { |product_usage| product_usage[:usage][:estimated_cost][:subunits] }.reduce(:+) || 0
        end

        sig { returns(T.nilable(::Billing::Types::Numeric)) }
        def total_cost_in_subunits
          return if has_error?
          T.bind(self, T::Hash[Symbol, T.untyped])

          self[:product_usage].map { |product_usage| product_usage[:usage][:estimated_cost][:subunits] }.reduce(:+) || 0
        end
      end

      include Methods

      mixes_in_class_methods(Methods)
    end
  end
end
