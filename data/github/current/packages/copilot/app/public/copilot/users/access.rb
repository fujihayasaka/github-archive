# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Users
    module Access
      extend T::Helpers
      include Copilot::Users::Signatures
      include GitHub::Memoizer

      abstract!

      sig { override.returns(Symbol) }
      memoize def access_type
        copilot_authorizer_object_no_snippy.access_type
      end

      sig { override.returns(String) }
      memoize def access_type_sku
        copilot_authorizer_object_no_snippy.access_type_sku
      end

      sig { override.returns(T::Boolean) }
      memoize def has_cfb_access?
        return true if Copilot::Seat.exists?(assigned_user_id: T.must(user_object).id)

        async_seat_assignments.sync.any?
      end

      sig { override.returns(T::Boolean) }
      def has_cb_access?
        has_cfb_access?
      end

      sig { override.returns(T::Boolean) }
      memoize def has_cfe_access?
        copilot_authorizer_object_no_snippy.has_cfe_access?
      end

      sig { override.returns(T::Boolean) }
      def has_ce_access?
        has_cfe_access?
      end

      sig { override.returns(T::Boolean) }
      memoize def has_cfi_access?
        copilot_authorizer_object_no_snippy.has_cfi_access?
      end

      sig { override.returns(T::Boolean) }
      def has_ci_access?
        has_cfi_access?
      end

      sig { override.returns(T::Boolean) }
      def has_paid_access?
        copilot_authorizer_object_no_snippy.has_paid_access?
      end

      sig { override.returns(T::Boolean) }
      def has_limited_access?
        copilot_authorizer_object_no_snippy.has_limited_access?
      end

      # this will check if the user has free access to Copilot because of an educational coupon or engaged oss
      # @return [Boolean] whether they have access
      sig { override.returns(T::Boolean) }
      def has_free_access?
        collect_metrics("copilot.has_free_access") do
          async_has_free_access?.sync
        end
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_access?
        has_paid_access? || has_free_access? || has_trial_subscription? || has_limited_access?
      end

      sig { override.returns(T.nilable(Copilot::AggregateUsageDetail)) }
      def latest_usage_detail
        Copilot::AggregateUsageDetail.latest_for_users(user_object)
      end

      sig { override.returns(T.nilable(T.any(Copilot::Organization, Copilot::Business))) }
      memoize def copilot_provider
        if copilot_user_object.has_copilot_standalone_business?
          # This has to be valid if the method above returns true.
          T.must(copilot_user_object.copilot_standalone_businesses&.first)
        end

        copilot_user_object.copilot_organization || copilot_user_object.copilot_business
      end

      sig { returns(T::Boolean) }
      memoize def has_o1_models_access?
        return false if has_limited_access?
        return true if user_object.feature_enabled?(:project_neutron_o1_models)

        copilot_public_user_object = Copilot::Public::User.new(user_object)

        return true if copilot_public_user_object.o1_enabled?

        false
      end

      private

      sig { returns(Promise[T::Boolean]) }
      def async_has_free_access?
        Platform::Loaders::ActiveRecord.load(::Copilot::FreeUser, user_object.id, column: :user_id).then do |free_user|
          if free_user.present?
            free_user.next_check_at > Date.current && free_user.subscribed?
          else
            Promise.resolve(false)
          end
        end
      end
    end
  end
end
