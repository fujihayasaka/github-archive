# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class Discount
        include GitHub::Memoizer
        include Billing::Platform::Api::Utils
        include ActiveModel::Model

        delegate :[], to: :discount_data

        sig { params(discount_data: T::Hash[Symbol, T.untyped]).void }
        def initialize(discount_data)
          @discount_data = T.let(discount_data.with_indifferent_access, T::Hash[Symbol, T.untyped])
        end

        sig { returns(T.nilable(::Billing::Types::Account)) }
        def owner
          target
        end

        sig { returns(T.any(String, Integer)) }
        def customer_id
          discount_data[:discount][:key][:customer_id]
        end

        sig { returns(String) }
        def resource_type
          resource_type = discount_data[:discount][:resource_type]
          case resource_type
          when "CUSTOMER", 1
            CUSTOMER_TARGET
          when "USER", 2
            USER_TARGET
          when "UNKNOWN_TARGET", 0
            "Unknown"
          else
            CUSTOMER_TARGET
          end
        end

        sig { returns(T.any(Integer, String)) }
        def resource_id
          discount_data[:discount][:resource_id]
        end

        sig { returns(T.nilable(T.any(String, Integer))) }
        def global_resource_id
          resource_id
        end

        sig { returns(String) }
        def pricing_target_type
          pricing_targets = discount_data[:discount][:pricing_targets] || []
          first_target = pricing_targets.first || {}
          first_target[:pricing_target_type]&.to_s || first_target[:type]&.to_s || "Unknown"
        end

        sig { returns(String) }
        def pricing_targets
          pricing_targets = discount_data[:discount][:pricing_targets] || []
          first_target = pricing_targets.first || {}
          first_target[:pricing_target_id]&.to_s || first_target[:id]&.to_s || ""
        end

        sig { returns(String) }
        def pricing_target_id
          pricing_targets
        end

        sig { returns(String) }
        def product_name
          "billing_platform_#{pricing_target_type}"
        end

        sig { returns(Float) }
        def target_amount
          discount_data[:discount][:target_amount].to_f
        end

        sig { returns(String) }
        def discount_type
          dt = discount_data[:discount][:discount_type]
          dt == "PERCENT" || dt == 4 ? "Percentage" : "Amount"
        end

        sig { returns(T::Boolean) }
        def fully_applied?
          discount_data.dig(:discount_state, :is_fully_applied)
        end

        sig { returns(Float) }
        def current_amount
          discount_data.dig(:discount_state, :current_amount).to_f
        end

        sig { returns(Integer) }
        def current_percentage
          return 0 if target_amount.zero?

          ((current_amount / target_amount) * 100).floor
        end

        sig { returns(String) }
        def uuid
          discount_data[:discount][:key][:uuid].to_s
        end

        sig { returns(T.nilable(T.any(::Billing::Types::Account, User))) }
        memoize def target
          case resource_type
          when CUSTOMER_TARGET
            Customer.find_by(id: resource_id)&.billable_owner
          when USER_TARGET
            User.find_by(id: resource_id)
          else
            nil
          end
        end

        sig { returns(String) }
        def target_name
          case target = self.target
          when Business
            target.slug
          when User
            target.name.presence || target.display_login.presence || "Unknown User"
          else
            ""
          end
        end

        sig { params(context: T.any(::Billing::Types::Account, Repository, User)).returns(T::Boolean) }
        def visible_to?(context)
          true
        end

        sig { returns(String) }
        def slug
          [uuid, target_amount].join("-")
        end

        sig { returns(Integer) }
        def threshold_percentage
          value = discount_data.dig(:discount_state, :discount_threshold, :minimum_usage_percentage)
          return 0 if value.nil?
          value.to_f.floor
        end

        private

        sig { returns(T::Hash[Symbol, T.untyped])  }
        attr_reader :discount_data

        sig do
          params(
            user: User,
            target: T.nilable(T.any(::Billing::Types::Account, User))
          ).returns(T::Boolean)
        end
        def discount_visible_to_user?(user, target)
          true
        end

        sig do
          params(
            business: Business,
            target: T.nilable(T.any(::Billing::Types::Account, User))
          ).returns(T::Boolean)
        end
        def discount_visible_to_business?(business, target)
          true
        end
      end
    end
  end
end
