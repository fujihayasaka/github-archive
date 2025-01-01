# typed: true
# frozen_string_literal: true

module TrustTiers

  # Current Tiers (as of 2022-02-22):
  # **************** TRUSTED ****************
  # * Sales serve accounts (invoiced Organization or invoiced Enterprises)
  #    *************   OR    *************
  # * Accounts with established billing history
  #     * Most recent payment was successful
  #     * One successful payment at least two months ago
  #    *************   OR    *************
  # * Oldest account owner > 14 days old AND has eligible coupon
  #
  # **************** NEUTRAL ****************
  # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful)
  #    *************   OR    *************
  # * Oldest account owner > 3 days old AND has eligible coupon
  #    *************   OR    *************
  # * Oldest account owner created more than 30 days ago
  #
  # **************** UNTRUSTED ****************
  # * Everyone else
  #
  class Tier
    TRUSTED = 1 # Most trusted customers with complete access to consumable resources.
    NEUTRAL = 2 # Neutral customers with controlled access to consumable resources
    UNTRUSTED = 3 # Least trusted customers with limited access to consumable resources

    STAFFTOOLS_CLIENT = "stafftools"

    def self.tier_name(tier)
      case tier
      when TRUSTED
        "Trusted"
      when NEUTRAL
        "Neutral"
      when UNTRUSTED
        "Untrusted"
      when -1
        "Calculating..."
      end
    end

    class Error < TrustTiers::Error; end
    class NoOwnersGivenError < TrustTiers::Tier::Error; end

    def self.for_repository(repository, client_name = Api::Internal::Twirp::UNKNOWN_CLIENT_NAME)
      ActiveRecord::Base.connected_to(role: :reading) do
        for_repository_internal(repository, client_name)
      end
    end

    def self.for_repository_internal(repository, client_name)
      owner = resolve_repository_owner(repository.owner)
      owner_details = TierDetails.new(owner)

      # check if the repository is an Engaged OSS Repo
      if EngagedOss.is_repo_engaged_oss?(repository.id)
        calculated_tier = TrustTiers::TierResult.new(TRUSTED, TierResult::ENGAGED_OSS)
      else
        calculated_tier = self.for_billable_owner(owner, client_name)
      end

      log_calculation_results(owner, owner_details, calculated_tier, client_name, "for_repository")
      calculated_tier
    end
    private_class_method :for_repository_internal

    # this returns a TierResult class
    def self.for_billable_owner(owner, client_name = Api::Internal::Twirp::UNKNOWN_CLIENT_NAME, force_calculation: false)
      ActiveRecord::Base.connected_to(role: :reading) do
        for_billable_owner_internal(owner, client_name, force_calculation)
      end
    end

    def self.for_billable_owner_internal(owner, client_name, force_calculation)
      return TrustTiers::TierResult.new(TRUSTED, TierResult::GITHUB_ENTERPRISE) if GitHub.enterprise?

      owner_details = TierDetails.new(owner)
      calculated_tier = calculate_tier(owner, owner_details, force_calculation: force_calculation)

      GitHub.dogstats.increment(
        "trust_tiers.calculate_tier",
        tags: [
          "client_name:#{client_name}",
          "tier:#{calculated_tier.tier}",
          "tier_reason:#{calculated_tier.reason}"
        ]
      )
      if owner.feature_enabled?(:trust_tier_1_business_test)
        owner_details_v2 = TierDetailsV2.new(owner)
        calculated_tier_v2 = calculate_tier_v2(owner, owner_details_v2, force_calculation: force_calculation)
        GitHub.dogstats.increment(
          "trust_tiers.calculate_tier_v2",
          tags: [
            "client_name:#{client_name}",
            "tier:#{calculated_tier_v2.tier}",
            "tier_reason:#{calculated_tier_v2.reason}"
          ]
        )
        GitHub.dogstats.increment(
          "trust_tiers.calculate_tier_difference",
          tags: [
            "client_name:#{client_name}",
            "invoiced:#{owner.invoiced?}",
            "business:#{owner.is_a?(Business)}",
            "business_trial: #{owner.is_a?(Business) ? owner.trial? : "NA"}",
            "new_tier:#{calculated_tier_v2.tier}",
            "new_tier_reason:#{calculated_tier_v2.reason}",
            "former_tier:#{calculated_tier.tier}",
            "former_tier_reason:#{calculated_tier.reason}",
            "tier_difference:#{calculated_tier_v2.tier - calculated_tier.tier}"
          ]
        )
        log_calculation_results(
          owner,
          owner_details_v2,
          calculated_tier_v2,
          client_name, "for_billable_owner_v2",
          v2_tier_difference: calculated_tier_v2.tier - calculated_tier.tier,
          former_calculated_tier: calculated_tier.tier,
          former_tier_reason: calculated_tier.reason
        )
      end

      log_calculation_results(
        owner,
        owner_details,
        calculated_tier,
        client_name,
        "for_billable_owner"
      )

      if owner.feature_enabled?(:trust_tier_1_business_test) && owner.feature_enabled?(:billing_update_trust_tier_rules) && !owner.feature_enabled?(:trust_tier_updates_business_exclusion)
        calculated_tier_v2
      else
        calculated_tier
      end
    end
    private_class_method :for_billable_owner_internal

    class << self
      private

      # this calculates things and returns a TrustTiers::TierResult
      def calculate_tier(owner, owner_details, force_calculation: false)
        # for stafftools, we will pass in the force_calculation flag to see what the tier WOULD have been
        unless force_calculation || owner.is_a?(Business) # this is only for orgs since Businesses don't have settings
          # Check the user's settings for the forced tier - default value is -1 which means no forced tier
          # we need to check it here because Businesses don't have settings

          forced_tier = owner.settings.get(:trust_tier)

          if forced_tier > 0
            GitHub.dogstats.increment(
              "trust_tiers.tier_for_organization",
              tags: [
                "tier:#{forced_tier}",
                "tier_reason:#{TierResult::SETTINGS_FORCED}"
              ]
            )

            GitHub.logger.info(
              "code.namespace" => self.class.name,
              "code.function" => "tier_for_organization",
              "gh.catalog_service" => "github/trust_tiers",
              "gh.owner.database_id" => owner.id,
              "gh.owner.global_id" => owner.global_relay_id,
              "calculated_tier" => forced_tier,
              "tier_reason" => TierResult::SETTINGS_FORCED
            )

            return TrustTiers::TierResult.new(forced_tier, TierResult::SETTINGS_FORCED)
          end
        end


        # **************** TRUSTED ****************
        # * Sales serve accounts (invoiced Organization or Enterprise)
        if (owner.is_a?(Business) && !owner.trial?) || owner.invoiced?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::BUSINESS_OR_INVOICED)
        end

        # **************** TRUSTED ****************
        # * Accounts with established billing history
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        if !owner_details.last_payment_failed? && owner_details.has_established_billing_history?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::ESTABLISHED_BILLING)
        end

        # **************** TRUSTED ****************
        # * Oldest account owner > 14 days old AND has eligible coupon
        if owner_details.has_eligible_coupon? && owner_details.oldest_owner_older_than_trusted_couponed_age_limit?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::TRUSTED_COUPON)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner created more than 30 days ago
        if owner_details.oldest_owner_older_than_neutral_free_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::OLDEST_OWNER_AGE)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful)
        if owner_details.has_paid_money? && !owner_details.last_payment_failed? && owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::PAID)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner > 3 days old AND has eligible coupon
        if owner_details.has_eligible_coupon? && owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::COUPON)
        end

        # **************** UNTRUSTED ****************
        # * Enterprise trial accounts
        if (owner.is_a?(Business) && owner.trial?) || (owner.respond_to?(:business) && owner.business&.trial?)
          return TrustTiers::TierResult.new(UNTRUSTED, TierResult::ENTERPRISE_TRIAL)
        end

        # **************** UNTRUSTED ****************
        # * Everyone else
        TrustTiers::TierResult.new(UNTRUSTED, TierResult::NO_MATCH)
      end

      def calculate_tier_v2(owner, owner_details, force_calculation: false)
        # for stafftools, we will pass in the force_calculation flag to see what the tier WOULD have been
        unless force_calculation || owner.is_a?(Business) # this is only for orgs since Businesses don't have settings
          # Check the user's settings for the forced tier - default value is -1 which means no forced tier
          # we need to check it here because Businesses don't have settings

          forced_tier = owner.settings.get(:trust_tier)

          if forced_tier > 0
            GitHub.dogstats.increment(
              "trust_tiers.tier_for_organization",
              tags: [
                "tier:#{forced_tier}",
                "tier_reason:#{TierResult::SETTINGS_FORCED}"
              ]
            )

            GitHub.logger.info(
              "code.namespace" => self.class.name,
              "code.function" => "tier_for_organization",
              "gh.catalog_service" => "github/trust_tiers",
              "gh.owner.database_id" => owner.id,
              "gh.owner.global_id" => owner.global_relay_id,
              "calculated_tier" => forced_tier,
              "tier_reason" => TierResult::SETTINGS_FORCED
            )

            return TrustTiers::TierResult.new(forced_tier, TierResult::SETTINGS_FORCED)
          end
        end


        # **************** TRUSTED ****************
        # * Sales serve accounts (invoiced Organization or invoiced Enterprise)
        if owner.invoiced?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::BUSINESS_OR_INVOICED)
        end

        # **************** TRUSTED ****************
        # * Accounts with established billing history
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        if !owner_details.last_payment_failed? && owner_details.has_established_billing_history?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::ESTABLISHED_BILLING)
        end

        # **************** TRUSTED ****************
        # * Oldest account owner > 14 days old AND has eligible coupon
        if owner_details.has_eligible_coupon? && owner_details.oldest_owner_older_than_trusted_couponed_age_limit?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::TRUSTED_COUPON)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner created more than 30 days ago
        if owner_details.oldest_owner_older_than_neutral_free_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::OLDEST_OWNER_AGE)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful)
        if owner_details.has_paid_money? && !owner_details.last_payment_failed? && owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::PAID)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner > 3 days old AND has eligible coupon
        if owner_details.has_eligible_coupon? && owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::COUPON)
        end

        # **************** UNTRUSTED ****************
        # * Enterprise trial accounts
        if (owner.is_a?(Business) && owner.trial?) || (owner.respond_to?(:business) && owner.business&.trial?)
          return TrustTiers::TierResult.new(UNTRUSTED, TierResult::ENTERPRISE_TRIAL)
        end

        # **************** UNTRUSTED ****************
        # * Everyone else
        TrustTiers::TierResult.new(UNTRUSTED, TierResult::NO_MATCH)
      end

      def resolve_repository_owner(owner)
        owner = owner.business if owner.organization? && owner.business.present?
        owner
      end

      def log_calculation_results(owner, owner_details, calculated_tier, client_name, fn, v2_tier_difference: 0, former_calculated_tier: nil, former_tier_reason: nil)
        GitHub.logger.info(
          "code.namespace" => name,
          "code.function" => fn,
          "gh.enterprise" => GitHub.enterprise?,
          "gh.catalog_service" => "github/trust_tiers",
          "gh.owner.database_id" => owner.id,
          "gh.owner.global_id" => owner.global_relay_id,
          "gh.owner.invoiced" => owner.invoiced?,
          "gh.owner.business" => owner.is_a?(Business),
          "gh.owner.trial" => owner.is_a?(Business) ? owner.trial? : "NA",
          "has_eligible_coupon" => owner_details.has_eligible_coupon?,
          "has_established_billing_history" => owner_details.has_established_billing_history?,
          "last_payment_failed" => owner_details.last_payment_failed?,
          "has_paid_money" => owner_details.has_paid_money?,
          "is_paid_plan" => owner_details.is_paid_plan?,
          "oldest_owner_older_than_trusted_couponed_age_limit" => owner_details.oldest_owner_older_than_trusted_couponed_age_limit?,
          "oldest_owner_older_than_neutral_free_age_limit" => owner_details.oldest_owner_older_than_neutral_free_age_limit?,
          "oldest_owner_older_than_neutral_paid_or_couponed_age_limit" => owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?,
          "oldest_owner_age" => owner_details.oldest_owner_age,
          "oldest_owner" => owner_details.oldest_owner,
          "client_name" => client_name,
          "calculated_tier" => calculated_tier.tier,
          "tier_reason" => calculated_tier.reason,
          "former_calculated_tier" => former_calculated_tier,
          "former_tier_reason" => former_tier_reason,
          "v2_tier_difference" => v2_tier_difference
        )
      end
    end
  end
end
