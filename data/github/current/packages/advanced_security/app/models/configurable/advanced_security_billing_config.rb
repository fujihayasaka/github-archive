# typed: true
# frozen_string_literal: true

# Whether a customer (enterprise account or org) has purchased GitHub Advanced Security
#
# Data for advanced_security_purchased_for_entity? and advanced_security_seats are stored separately
# although it is forbidden to have to have seats set when GHAS is not enabled.
# If GHAS is enabled but seats is nil or 0, then this is treated as having unlimited seats.
# This provides a natural upgrade path for enterprises that existed before advanced_security_seats.
# (Orgs don't need this upgrade path as they didn't have this config in the past, but the
# concept of unlimited seats is still relevant for them.)
#
# These methods do NOT hand off to an org's business (if it has one) when called on an org.
# Therefore, you should exercise caution when calling them.
#
# If an org's business has GHAS enabled but the org itself doesn't (which is the normal state
# of affairs for an org in a GHAS business) these methods will return false/0 for the org.
#
# For this reason, you should normally call advanced_security_purchased?
# and advanced_security_seats as those handle checking against the business where one is
# present as well as checking other edge cases.
#
# These methods should only be called where you explicitly only want to check
# the org or business entity itself.
#
# This module is not relevant in GHES, where GHAS enablement and number of seats is
# instead controlled by the license.
module Configurable
  module AdvancedSecurityBillingConfig

    # Are the suite of products under Advanced Security being given to the customer as a single bundled offering
    # or split into multiple offerings. Default state is bundled to be backwards compatible against previous default
    # offering.
    ADVANCED_SECURITY_BUNDLED_KEY = "advanced_security.bundled"
    ADVANCED_SECURITY_KEY = "advanced_security"

    # A set of constants that represent the different types of advanced security enablement
    ADVANCED_SECURITY_OFF = "off" # do not set as a value in the DB, we delete the key when advanced security is not purchased
    GHAS_VOLUME = "true" # this is legacy from the config.enable method before converting to a text field
    GHAS_METERED = "enabled_with_metered_billing"
    SPLIT_METERED = "split_metered"
    SPLIT_VOLUME = "split_volume_all"
    SECRET_PROTECTION_VOLUME = "split_secret_scanning_only"
    CODE_SECURITY_VOLUME = "split_code_security_only"

    # Old, deprecated constants aliased to the new ones due to GitHubbian risk-aversion
    ADVANCED_SECURITY_ENABLED = GHAS_VOLUME
    ADVANCED_SECURITY_ENABLED_METERED_BILLING = GHAS_METERED
    ADVANCED_SECURITY_SPLIT_METERED = SPLIT_METERED
    SPLIT_VOLUME_ALL = SPLIT_VOLUME
    SPLIT_VOLUME_SECRET_SCANNING_ONLY = SECRET_PROTECTION_VOLUME
    SPLIT_VOLUME_CODE_SECURITY_ONLY = CODE_SECURITY_VOLUME

    # Enablement               | GHAS purchased | Secret Protection purchased  | Code Security purchased | Billing mode
    # -----------------------------------------------------------------------------------------------------------------
    # ADVANCED_SECURITY_OFF    | false          | false                        | false                   | N/A
    # GHAS_VOLUME              | true           | false                        | false                   | volume
    # GHAS_METERED             | true           | false                        | false                   | metered
    # SPLIT_METERED            | false          | true                         | true                    | metered
    # SPLIT_VOLUME             | false          | true                         | true                    | volume
    # SECRET_PROTECTION_VOLUME | false          | true                         | false                   | volume
    # CODE_SECURITY_VOLUME     | false          | false                        | true                    | volume

    ## When GHAS_VOLUME, we use these secondary config values
    ADVANCED_SECURITY_SEATS_KEY = "advanced_security.seats"
    ADVANCED_SECURITY_MAX_NUMBER_OF_SEATS = 1_000_000

    ## When SPLIT_VOLUME or SECRET_PROTECTION_VOLUME
    SECRET_SCANNING_LICENSE_KEY = "secret_scanning.license_count"

    ## When SPLIT_VOLUME or CODE_SECURITY_VOLUME
    CODE_SECURITY_LICENSE_KEY = "code_security.license_count"

    class SubscriptionNotFoundError < StandardError; end
    class SubcriptionUpdateError < StandardError; end
    class SubscriptionQuantityCannotBeZero < StandardError; end

    class DunningError < StandardError; end

    sig { returns(String) }
    def advanced_security_enabled_type_for_entity
      T.bind(self, T.any(Organization, Business))

      return ADVANCED_SECURITY_OFF unless advanced_security_purchased_for_entity?
      config.get(ADVANCED_SECURITY_KEY)
    end

    # atomic method to set the advanced security enabled type for an entity (including turning off)
    # ensuring any side-effects are modified for all types.
    sig { params(option: String, actor: User, is_stafftools_action: T::Boolean).void }
    def set_advanced_security_enabled_type_for_entity(option:, actor:, is_stafftools_action: false)
      T.bind(self, T.any(Organization, Business))

      return unless option.present?

      case option
      when GHAS_VOLUME, GHAS_METERED,
        SPLIT_METERED, SPLIT_VOLUME, SECRET_PROTECTION_VOLUME,
        CODE_SECURITY_VOLUME
        raise_if_organization_is_ineligible!

        # nothing to do if ghas is already purchased
        return if config.local?(ADVANCED_SECURITY_KEY) && config.get(ADVANCED_SECURITY_KEY) == option
        config.set(ADVANCED_SECURITY_KEY, option, actor)
        @advanced_security_purchased_for_entity = nil
      when ADVANCED_SECURITY_OFF
        # we delete the key here ensuring the absence of the key is always how we represent
        # GHAS being OFF for an entity.
        config.delete(ADVANCED_SECURITY_KEY, actor)
        @advanced_security_purchased_for_entity = nil
      else
        raise ArgumentError, "Invalid option: #{option}"
      end

      toggle_state = option != ADVANCED_SECURITY_OFF

      message = {
        actor: actor,
        toggle_state: toggle_state
      }

      # Note: Event instrumentation below is currently the same for bundled as well as split-SKUs.
      # This is because both turboGHAS and security overview care only about feature enablement, not SKU purchases, so
      # the 'advanced_security' toggled events will account for whichever feature is being toggled.
      # However, this is not ideal in terms of long-term code readability, so we shall eventually
      # add new instrumentation for the split SKU scenarios: https://github.com/github/secret-scanning/issues/11325

      # Instrument billing toggled event for turboGHAS
      message[:organization] = self if self.is_a?(Organization)
      message[:business] = self if self.is_a?(Business)
      GlobalInstrumenter.instrument("advanced_security_billing.billing_toggled", message)

      # Instrument advanced_security_license_toggled and advanced_security_toggled events for security overview.
      if self.is_a?(Organization)
        GlobalInstrumenter.instrument("security_products.organization_advanced_security_license_toggled", {
          organization_id: self.id,
          enabled: toggle_state,
          license_toggled_for_org_at: Time.now.utc,
        })
      elsif self.is_a?(Business)
        GlobalInstrumenter.instrument("security_products.enterprise_advanced_security_license_toggled", {
          business_id: self.id,
          enabled: toggle_state,
          license_toggled_at: Time.now.utc,
        })
      end

      instrument("advanced_security_toggled", { id: id })
    end

    sig { void }
    def raise_if_organization_is_ineligible!
      T.bind(self, T.any(Organization, Business))

      return unless GitHub.flipper[:ghec_disabled_for_organizations_linked_to_enterprise].enabled?(self)
      return unless GitHub.billing_enabled?
      return unless is_a?(Organization)

      if dunning?
        raise DunningError.new "Organization is not eligible for GHAS since it's in a dunning state."
      end

      return unless business.present?
      return unless plan.business_plus?

      if business&.trial?
        raise ArgumentError, "Organization is not eligible for GHAS since parent business is on a free trial"
      end

      raise ArgumentError, "Organization is not on a GHEC plan or is a child of an Enterprise, and therefore cannot purchase GHAS"
    end

    sig { params(actor: User).void }
    def mark_advanced_security_as_not_purchased_for_entity(actor:)
      T.bind(self, T.any(Organization, Business))
      set_advanced_security_enabled_type_for_entity(option: ADVANCED_SECURITY_OFF, actor: actor)
    end

    sig { params(actor: User, is_stafftools_action: T::Boolean).void }
    def mark_advanced_security_as_purchased_for_entity(actor:, is_stafftools_action: false)
      T.bind(self, T.any(Organization, Business))
      set_advanced_security_enabled_type_for_entity(option: GHAS_VOLUME, actor: actor, is_stafftools_action: is_stafftools_action)
    end

    sig { params(actor: User, is_stafftools_action: T::Boolean).void }
    def mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor:, is_stafftools_action: false)
      T.bind(self, T.any(Organization, Business))
      set_advanced_security_enabled_type_for_entity(option: SPLIT_VOLUME, actor: actor, is_stafftools_action: is_stafftools_action)
    end

    sig { params(actor: User).void }
    def mark_advanced_security_as_metered_for_entity(actor:)
      T.bind(self, T.any(Organization, Business))
      set_advanced_security_enabled_type_for_entity(option: GHAS_METERED, actor: actor)
    end

    sig { params(actor: User).void }
    def set_customer_to_split_metered_offering(actor:)
      T.bind(self, T.any(Organization, Business))
      set_advanced_security_enabled_type_for_entity(option: SPLIT_METERED, actor: actor)
    end

    sig { params(actor: User).void }
    def mark_secret_protection_as_purchased_for_entity_as_volume(actor:)
      T.bind(self, T.any(Organization, Business))
      set_advanced_security_enabled_type_for_entity(option: SECRET_PROTECTION_VOLUME, actor: actor)
    end

    sig { params(actor: User).void }
    def set_customer_to_split_volume_code_security_only(actor:)
      T.bind(self, T.any(Organization, Business))
      set_advanced_security_enabled_type_for_entity(option: CODE_SECURITY_VOLUME, actor: actor)
    end

    # See comment at top of file. This method only considers this entity
    # and does not consider any relationships between orgs and businesses.
    # this method also does not discern between billing types.
    #
    # Deprecated: This method returns true if anything is purchased, even if it's Secret Protection or Code Security.
    # Use ghas_sku_purchased_for_entity? or any_security_sku_purchased_for_entity? instead.
    sig { returns(T::Boolean) }
    def advanced_security_purchased_for_entity?
      T.bind(self, T.any(Organization, Business))

      return false if new_record?
      return false if entity_state_blocks_advanced_security?
      return false unless config.local?(ADVANCED_SECURITY_KEY)
      @advanced_security_purchased_for_entity ||= config.get(ADVANCED_SECURITY_KEY).present?
    end

    # This method only considers this entity and does not consider any relationships between orgs and businesses.
    # This method does not distinguish between metered/volume billing types.
    # This method only considers the unbundled/split offering of Code Security, not the bundled GHAS offering.
    sig { returns(T::Boolean) }
    def any_security_sku_purchased_for_entity?
      T.bind(self, T.any(Organization, Business))
      self.ghas_sku_purchased_for_entity? || self.secret_protection_sku_purchased_for_entity? || self.code_security_sku_purchased_for_entity?
    end

    sig { returns(T::Boolean) }
    def ghas_sku_purchased_for_entity?
      T.bind(self, T.any(Organization, Business))

      return false if new_record?
      return false if entity_state_blocks_secret_protection?
      return false unless config.local?(ADVANCED_SECURITY_KEY)

      val = config.get(ADVANCED_SECURITY_KEY)
      return false unless val.present?
      [GHAS_VOLUME, GHAS_METERED].include?(val)
    end

    sig { returns(T::Boolean) }
    def secret_protection_sku_purchased_for_entity?
      T.bind(self, T.any(Organization, Business))

      return false if new_record?
      return false if entity_state_blocks_secret_protection?
      return false unless config.local?(ADVANCED_SECURITY_KEY)

      val = config.get(ADVANCED_SECURITY_KEY)
      return false unless val.present?
      [SPLIT_VOLUME, SECRET_PROTECTION_VOLUME, SPLIT_METERED].include?(val)
    end

    sig { returns(T::Boolean) }
    def code_security_sku_purchased_for_entity?
      T.bind(self, T.any(Organization, Business))

      return false if new_record?
      return false if entity_state_blocks_advanced_security?
      return false unless config.local?(ADVANCED_SECURITY_KEY)
      [
        SPLIT_METERED,
        SPLIT_VOLUME,
        CODE_SECURITY_VOLUME,
      ].include?(config.get(ADVANCED_SECURITY_KEY))
    end

    # See comment at top of file. This method only considers this entity
    # and does not consider any relationships between orgs and businesses.
    sig { returns(T::Boolean) }
    def advanced_security_metered_for_entity?
      T.bind(self, T.any(Organization, Business))
      return false unless advanced_security_purchased_for_entity?
      [
        GHAS_METERED,
        SPLIT_METERED
      ].include?(config.get(ADVANCED_SECURITY_KEY))
    end

    # This method only considers this entity and does not consider any relationships between orgs and businesses.
    # This method does not distinguish between metered/volume billing types.
    # This method only considers the unbundled/split offering of Secret Protection, not the bundled GHAS offering.
    sig { returns(T::Boolean) }
    def secret_protection_purchased_for_entity?
      T.bind(self, T.any(Organization, Business))

      return false if new_record?
      return false if entity_state_blocks_advanced_security?
      return false unless config.local?(ADVANCED_SECURITY_KEY)
      [
        SPLIT_METERED,
        SPLIT_VOLUME,
        SECRET_PROTECTION_VOLUME,
      ].include?(config.get(ADVANCED_SECURITY_KEY))
    end

    sig do
      params(
        seats: Integer,
        actor: User,
        is_stafftools_action: T::Boolean,
      ).returns(
        T.any(T::Boolean, SubscriptionNotFoundError, SubscriptionQuantityCannotBeZero, SubcriptionUpdateError)
      )
    end
    def set_advanced_security_seats_for_entity(seats:, actor:, is_stafftools_action: false)
      T.bind(self, T.any(Business, Organization))

      raise_if_organization_is_ineligible!

      is_self_serve_advanced_security = advanced_security_seats_stored_on_subscription_item?

      if is_self_serve_advanced_security && advanced_security_subscription_item.nil?
        error_message = "Cannot set the number of self-serve GitHub Advanced Security seats because the subscription has not been purchased"
        return report_error(SubscriptionNotFoundError.new(error_message))
      elsif is_self_serve_advanced_security && advanced_security_subscription_item.present?
        if seats.zero?
          error_message = "Cannot set the number of self-serve GitHub Advanced Security seats to 0: to set it to 0, cancel the subscription"
          return report_error(SubscriptionQuantityCannotBeZero.new(error_message))
        else
          update = Billing::Public::SubscriptionItem.update(
            product: ::AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT,
            account: self,
            quantity: seats,
            actor: actor,
            is_stafftools_action: is_stafftools_action,
          )

          return report_error(SubcriptionUpdateError.new(update.to_s)) unless update.ok?
        end
      else
        config.set(ADVANCED_SECURITY_SEATS_KEY, seats, actor)
      end

      true
    end

    sig do
      params(
        error: T.any(SubscriptionNotFoundError, SubscriptionQuantityCannotBeZero, SubcriptionUpdateError)
      ).returns(
        T.any(SubcriptionUpdateError, SubscriptionQuantityCannotBeZero, SubscriptionNotFoundError)
      )
    end
    def report_error(error)
      GitHub.dogstats.increment("billing.ghas.set_advanced_security_seats_for_entity.error")
      Failbot.report(error, catalog_service: "github/advanced_security_billing")

      error
    end

    # See comment at top of file. This method only considers this entity
    # and not consider any relationships between orgs and businesses.
    sig { returns(Integer) }
    def advanced_security_seats_for_entity
      T.bind(self, T.any(Organization, Business))
      return 0 if entity_state_blocks_advanced_security?
      return 0 unless advanced_security_purchased_for_entity?

      if advanced_security_seats_stored_on_subscription_item?
        advanced_security_subscription_item&.quantity.to_i
      else
        return 0 if new_record?
        return 0 unless config.local?(ADVANCED_SECURITY_SEATS_KEY)
        config.int(ADVANCED_SECURITY_SEATS_KEY) || 0
      end
    end

    sig { returns(T::Boolean) }
    def advanced_security_seats_stored_on_subscription_item?
      T.bind(self, T.any(Organization, Business))

      return false unless GitHub.billing_enabled?
      return false if is_a?(Organization) && !GitHub.flipper[:ghas_self_serve_orgs].enabled?(self)
      return false if is_a?(Organization) && self.delegate_billing_to_business?
      return false if is_a?(Organization) && !self.plan.name == "business_plus"
      return false if is_a?(Business) && !self_serve_payment?
      return false if advanced_security_trial_enabled_for_entity?
      # This was manually enabled via stafftools by sales-ops, see cases: https://github.com/github/octogrowth/issues/2098#issuecomment-1483219871
      return false if advanced_security_subscription_item.nil? && advanced_security_purchased_for_entity?

      true
    end

    sig { returns(T::Boolean) }
    def entity_state_blocks_advanced_security?
      T.bind(self, T.any(Organization, Business))
      return true if suspended?
      return true if self.business? && T.bind(self, Business).downgraded_to_free_plan?

      false
    end

    sig { returns(T::Boolean) }
    def entity_state_blocks_secret_protection?
      T.bind(self, T.any(Organization, Business))
      return true if suspended?
      return true if self.business? && T.bind(self, Business).downgraded_to_free_plan?

      false
    end

    sig { params(count: Integer, actor: User).void }
    def set_secret_scanning_license_count(count:, actor:)
      T.bind(self, T.any(Organization, Business))
      config.set(SECRET_SCANNING_LICENSE_KEY, count, actor)
    end

    sig { returns(Integer) }
    def secret_scanning_license_count
      T.bind(self, T.any(Organization, Business))

      return 0 if new_record?
      return 0 unless config.local?(SECRET_SCANNING_LICENSE_KEY)
      config.int(SECRET_SCANNING_LICENSE_KEY) || 0
    end

    sig { params(count: Integer, actor: User).void }
    def set_code_security_license_count(count:, actor:)
      T.bind(self, T.any(Organization, Business))
      config.set(CODE_SECURITY_LICENSE_KEY, count, actor)
    end

    sig { returns(Integer) }
    def code_security_license_count
      T.bind(self, T.any(Organization, Business))

      return 0 if new_record?
      return 0 unless config.local?(CODE_SECURITY_LICENSE_KEY)
      config.int(CODE_SECURITY_LICENSE_KEY) || 0
    end
  end
end
