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
        return false if all_assignments_revoked?
        return true if Copilot::Seat.exists?(assigned_user_id: T.must(user_object).id)
        async_seat_assignments.sync.any?
      end

      sig { override.returns(T.nilable(String)) }
      memoize def country_code
        return nil unless self.user_object.feature_flag_enabled?(:copilot_country_code, default: false)

        customer_id = Copilot::Public::User.for(self.user_object).billable_customer_ids.first
        return nil unless customer_id

        GitHub.logger.info("Found customer id for user #{self.user_object.id}: #{customer_id}")
        contact = ::Billing::Contact.find_by(customer_id: customer_id)
        return nil unless contact

        GitHub.logger.info("Found Billing::Contact for customer id #{customer_id}: #{contact.id}")
        T.must(contact).country_code
      end

      sig { override.returns(T::Boolean) }
      def has_cb_access?
        has_cfb_access?
      end

      sig { override.returns(T::Boolean) }
      def has_standalone_access?
        copilot_authorizer_object_no_snippy.has_standalone_access?
      end

      sig { override.returns(T::Boolean) }
      memoize def has_multi_access?
        copilot_authorizer_object_no_snippy.has_multi_access?
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

      # Determines whether the user is on a plan that has a higher tier they
      # could upgrade to. This is a presentation-only signal for IDE/CLI
      # surfaces — it must never be used as an authorization decision.
      #
      # Eligibility matrix:
      #   - Free / Limited (FREE_LIMITED_COPILOT)  -> true  (can sign up for paid)
      #   - Individual Education                   -> true
      #   - Individual (Pro)                       -> true
      #   - Individual Pro+                        -> true  (once Max SKU is launched)
      #   - Individual Max                         -> false (top of individual tier)
      #   - Business (CFB seat)                    -> false
      #   - Enterprise (CFE seat)                  -> false
      #   - No / unknown access                    -> false
      #
      # Errors are intentionally swallowed so that a bug in this
      # presentation-only field never breaks the surfaces that read it. The
      # rescue is instrumented so regressions remain observable.
      sig { override.returns(T::Boolean) }
      memoize def can_upgrade_plan?
        return false unless use_token_based_billing?
        return false if cfi_paid_plan_upgrade_restricted?

        access_type = copilot_authorizer_object_no_snippy.access_type
        return false if access_type.blank?

        # Free / Limited users can always upgrade to a paid individual plan.
        return true if Copilot::Authorization::AccessLoader::LIMITED_ACCESS_TYPES.include?(access_type)

        # Educational users can upgrade.
        return true if has_educational_access?

        # Paid individual subscribers (Pro / Pro+ / Max). Max is the top of
        # the individual tier and cannot upgrade further. Pro+ is only
        # treated as upgradeable once the Max SKU has launched and the user
        # meets trust tier requirements when the gate is active.
        if has_cfi_access?
          return false if has_max_access?
          pro_plus_upgradeable = has_pro_plus_access? &&
            user_object.feature_flag_enabled?(:copilot_max_sku_signup, default: false) &&
            (!FeatureFlag.vexi.enabled?(:copilot_max_trust_tier_gate, user_object, default: false) ||
              TrustTiers::Tier.for_billable_owner(user_object).tier == TrustTiers::Tier::TRUSTED)
          return true if pro_plus_upgradeable || has_pro_access?
        end

        # Anything else (Business, Enterprise, no access, blocked, unknown
        # SKU) is not upgradeable from this surface.
        false
      rescue StandardError => e
        GitHub.dogstats.increment("copilot.user.can_upgrade_plan.error")
        GitHub.logger.warn(
          "Copilot::Users::Access#can_upgrade_plan? raised; defaulting to false",
          "gh.user.id" => user_object.id,
          "error.class" => e.class.name,
          "error.message" => e.message,
        )
        false
      end

      sig { returns(T::Boolean) }
      memoize def has_cfi_pro_plus_access?
        # Deprecated: use has_pro_plus_access? instead
        # TODO: remove this method when sure it is not being called.
        GitHub.logger.warn("Deprecated `has_cfi_pro_plus_access?` has been used.")
        has_pro_plus_access?
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

      sig { override.returns(T::Boolean) }
      def has_pro_access?
        copilot_authorizer_object_no_snippy.has_pro_access?
      end

      sig { override.returns(T::Boolean) }
      memoize def has_pro_plus_access?
        copilot_authorizer_object_no_snippy.has_pro_plus_access?
      end

      sig { override.returns(T::Boolean) }
      def has_max_access?
        copilot_authorizer_object_no_snippy.has_max_access?
      end

      sig { override.returns(T::Boolean) }
      def meets_trust_tier_requirements_for_max?
        return true unless FeatureFlag.vexi.enabled?(:copilot_max_trust_tier_gate, user_object, default: false)

        TrustTiers::Tier.for_billable_owner(user_object).tier == TrustTiers::Tier::TRUSTED
      end

      # this will check if the user has free access to Copilot because of an educational coupon or engaged oss
      # @return [Boolean] whether they have access
      sig { override.returns(T::Boolean) }
      def has_free_access?
        collect_metrics("copilot.has_free_access") do
          async_has_free_access?.sync
        end
      end

      sig { override.returns(T::Boolean) }
      def has_educational_access?
        copilot_authorizer_object_no_snippy.has_educational_access?
      end

      sig { returns(T::Boolean) }
      memoize def has_copilot_access?
        has_paid_access? || has_free_access? || has_trial_subscription? || has_limited_access?
      end

      # Private: Used exclusively in a stafftools component
      sig { override.returns(T.nilable(Copilot::Activity)) }
      def latest_usage_detail
        seats = Copilot::Seat.for_user(user_object)

        return nil if seats.empty?

        Copilot::Activity.where(copilot_seat_id: seats.pluck(:id)).order(activity_at: :desc).first
      end

      # Returns the display product name for the user's highest managed plan SKU.
      # Used by billing UI components to show which plan the user is on.
      sig { returns(String) }
      memoize def managed_plan_product_name
        return "GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME}" if has_cfe_access? || copilot_user_object.copilot_plan == "enterprise"
        return "GitHub #{Copilot::BUSINESS_PRODUCT_NAME}" if has_cfb_access? || copilot_user_object.has_copilot_standalone_business?
        return Copilot::INDIVIDUAL_MAX_PRODUCT_NAME if has_max_access?
        return Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_NAME if has_pro_plus_access?
        return Copilot::INDIVIDUAL_PRO_PRODUCT_NAME if has_pro_access?
        Copilot::INDIVIDUAL_FREE_PRODUCT_NAME
      end

      sig { override.returns(T.nilable(T.any(Copilot::Organization, Copilot::Business))) }
      memoize def copilot_provider
        if copilot_user_object.has_copilot_standalone_business?
          # This has to be valid if the method above returns true.
          return T.must(copilot_user_object.copilot_standalone_businesses&.first)
        end
        copilot_public_user_object = Copilot::Public::User.for(user_object)
        copilot_org = copilot_public_user_object.copilot_organizations.find do |co|
          co.copilot_plan == copilot_user_object.copilot_plan
        end

        return copilot_org if copilot_org

        if copilot_user_object.has_copilot_access_through_business?
          T.must(copilot_user_object.copilot_businesses_including_unaffiliated_and_outside_collaborators.first)
        else
          nil
        end
      end

      sig { returns(T::Boolean) }
      memoize def has_o1_models_access?
        return false if has_limited_access?
        return true if GitHubModels::Kv.get_o1_models_access_override(user_object.id)

        copilot_public_user_object = Copilot::Public::User.for(user_object)

        return true if copilot_public_user_object.o1_enabled?

        false
      end

      sig { returns(T::Boolean) }
      memoize def show_copilot_functionality?
        return true if user_object.is_enterprise_managed?
        return true if has_cb_access? || has_ce_access?
        return true if has_cfi_access? && !has_limited_access?

        user_object.settings.get(:copilot_show_functionality)
      end

      sig { returns(T::Boolean) }
      memoize def user_has_copilot_product_coupon?
        return true if user_object.coupon&.product_target&.product_uuid&.product_type == ::Billing::ProductUUID::COPILOT_PRODUCT_TYPE
        false
      end

      sig { returns(T::Boolean) }
      def cfi_paid_plan_upgrade_restricted?
        # When we're not restricting ALL paid signups, we check the following conditions
        return false unless user_object.feature_flag_enabled?(:copilot_disable_cfi_sku_new_signups, default: false)

        # ENABLE this flag for a user if we want to bypass the restriction and allow the user to go from Free --> CFI
        return false if user_object.feature_flag_enabled?(:copilot_enable_cfi_sku_new_signups, default: false)

        # DISABLE this flag if coupon holders should NOT bypass the restriction
        return false if user_object.feature_flag_enabled?(:copilot_enable_cfi_signup_for_coupon_holders, default: false) && user_has_copilot_product_coupon?

        # restrict limited access users and users who are blocked or have no access
        has_limited_access? || !has_cfi_access?
      end

      sig { override.returns(T::Boolean) }
      def copilot_max_new_signup_enabled?
        return true if FeatureFlag.vexi.enabled?(:copilot_enable_max_net_new_signup, user_object, default: false)
        return false if has_free_access? && !has_educational_access?
        has_pro_access? || has_pro_plus_access?
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
