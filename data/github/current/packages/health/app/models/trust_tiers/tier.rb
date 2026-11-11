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
    extend Scientist

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
      if owner.feature_flag_enabled_or_raise?(:trust_tier_1_business_test) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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

      if owner.feature_flag_enabled_or_raise?(:trust_tier_1_business_test) && owner.feature_flag_enabled_or_raise?(:billing_update_trust_tier_rules) && !owner.feature_flag_enabled_or_raise?(:trust_tier_updates_business_exclusion) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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
        science("trust_tiers.calculate_tier") do |e|
          e.use do
            calculate_tier_control(owner, owner_details, force_calculation: force_calculation)
          end

          e.try do
            # Create a separate instance of owner details and persisted owner objects so query counts
            # and memoization isn't affected when running control vs candidate calculations.
            candidate_owner = owner.class.find_by(id: owner.id) || owner
            candidate_owner_details = TierDetails.new(candidate_owner)
            calculate_tier_candidate(candidate_owner, candidate_owner_details, force_calculation: force_calculation)
          end

          e.after_run do |result|
            control_result = result.control.value
            candidate_result = result.candidates.first&.value

            if candidate_result.nil?
              GitHub.logger.info(
                "Trust tier calculation error - candidate is nil",
                "code.namespace":   self.class.name,
                "code.function":    "calculate_tier",
                "gh.owner.id":      owner.id
              )
              next
            end

            mismatch = control_result != candidate_result

            # Record metrics to datadog for every case where the experiment ran, so we can determine
            # the percentage of requests that will classify accounts in different tiers.
            GitHub.dogstats.increment("trust_tiers.tier_calculation_result", tags: [
              "version:v1",
              "mismatch:#{mismatch}",
              "control_tier:#{control_result.tier}",
              "control_reason:#{control_result.reason}",
              "candidate_tier:#{candidate_result.tier}",
              "candidate_reason:#{candidate_result.reason}"
            ])

            # Also log details about individual mismatches to Splunk for further analysis.
            if mismatch
              GitHub.logger.info(
                "Trust tier calculation mismatch",
                "code.namespace":   self.class.name,
                "code.function":    "calculate_tier",
                "gh.owner.id":      owner.id,
                "control_tier":     control_result.tier,
                "control_reason":   control_result.reason,
                "candidate_tier":   candidate_result.tier,
                "candidate_reason": candidate_result.reason
              )
            end

            GitHub.hydro_publisher.publish(
              {
                control_trust_tier: control_result.tier,
                candidate_trust_tier: candidate_result.tier,
                control_reason: control_result.reason.to_s,
                candidate_reason: candidate_result.reason.to_s,
                mismatch: mismatch,
                database_id: owner.id,
                global_relay_id: owner.global_relay_id,
                entity_type: owner.class.name,
                experiment_name: "trust_tiers.calculate_tier",
              },
              schema: "github.trust_tier_science.v0.TrustTierScience",
              partition_key: owner.id,
              topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
            )
          end
        end
      end

      # this calculates things and returns a TrustTiers::TierResult
      def calculate_tier_control(owner, owner_details, force_calculation: false)
        # for stafftools, we will pass in the force_calculation flag to see what the tier WOULD have been
        unless force_calculation
          forced_tier = forced_tier_for_owner(owner)

          if forced_tier > 0
            return TrustTiers::TierResult.new(forced_tier, TierResult::SETTINGS_FORCED)
          end
        end

        # **************** TRUSTED ****************
        # * Sales serve accounts (invoiced Organization or Enterprise)
        if (owner.is_a?(Business) && !owner.trial?) || owner.invoiced?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::BUSINESS_OR_INVOICED)
        end

        # **************** UNTRUSTED ****************
        # * Accounts with billing disputes/chargebacks
        if owner_details.has_disputes?
          return TrustTiers::TierResult.new(UNTRUSTED, TierResult::DISPUTED_ACCOUNT)
        end

        # **************** TRUSTED ****************
        # * Accounts with established billing history (including IAP)
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        if !owner_details.last_payment_failed? && owner_details.has_established_billing_history_or_iap?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::ESTABLISHED_BILLING)
        end

        # **************** TRUSTED ****************
        # * Oldest account owner > 14 days old AND has eligible coupon
        if owner_details.has_eligible_coupon? && owner_details.oldest_owner_older_than_trusted_couponed_age_limit?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::TRUSTED_COUPON)
        end

        # **** NOT QUITE READY FOR NEUTRAL YET ****
        # New-ish account with:
        #   - an account timezone/last_ip country mismatch or
        #   - an email address with a farmable domain
        if owner_details.is_user? && owner_details.account_age_in_days < 14
          if owner_details.time_zone_mismatched?
            return TrustTiers::TierResult.new(UNTRUSTED, TierResult::MISMATCHED_TIMEZONE)
          end

          if owner_details.has_farmable_email_domain?
            return TrustTiers::TierResult.new(UNTRUSTED, TierResult::FARMABLE_DOMAIN)
          end
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner created more than 30 days ago
        if owner_details.oldest_owner_older_than_neutral_free_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::OLDEST_OWNER_AGE)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful, including IAP)
        if owner_details.has_paid_money_or_iap? && !owner_details.last_payment_failed? && owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
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

      # this calculates things and returns a TrustTiers::TierResult,
      # including experimental logic we want to audit with Scientist before actually changing behavior
      def calculate_tier_candidate(owner, owner_details, force_calculation: false)
        # for stafftools, we will pass in the force_calculation flag to see what the tier WOULD have been
        unless force_calculation
          forced_tier = forced_tier_for_owner(owner)

          if forced_tier > 0
            return TrustTiers::TierResult.new(forced_tier, TierResult::SETTINGS_FORCED)
          end
        end

        # **************** TRUSTED ****************
        # * Sales serve accounts (invoiced Organization or Enterprise)
        if (owner.is_a?(Business) && !owner.trial?) || owner.invoiced?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::BUSINESS_OR_INVOICED)
        end

        # **************** UNTRUSTED ****************
        # * Accounts with billing disputes/chargebacks
        if owner_details.has_disputes?
          return TrustTiers::TierResult.new(UNTRUSTED, TierResult::DISPUTED_ACCOUNT)
        end

        # **************** TRUSTED ****************
        # * Accounts with established billing history (including IAP)
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        if !owner_details.last_payment_failed? && owner_details.has_established_billing_history_or_iap?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::ESTABLISHED_BILLING)
        end

        # **************** TRUSTED ****************
        # * Orgs/businesses with established billing history whose last payment failed (lapsed payment grace)
        if owner.feature_flag_enabled_or_raise?(:trust_tier_org_lapse_grace) && owner_details.eligible_for_lapsed_payment_grace? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          return TrustTiers::TierResult.new(TRUSTED, TierResult::ESTABLISHED_BILLING_LAPSED_PAYMENT)
        end

        # **************** TRUSTED ****************
        # * Oldest account owner > 14 days old AND has eligible coupon
        if owner_details.has_eligible_coupon? && owner_details.oldest_owner_older_than_trusted_couponed_age_limit?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::TRUSTED_COUPON)
        end

        # **************** TRUSTED ****************
        # * Azure-metered orgs/enterprises with at least $100 of billed usage older than
        #   60 days. Azure billing produces no GitHub payment history, so established billing
        #   history never matches; instead we trust substantial aged Azure usage.
        if owner_details.is_azure_metered_with_billed_usage?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::AZURE_METERED_BILLING)
        end

        # **** NOT QUITE READY FOR NEUTRAL YET ****
        # New-ish account with:
        #   - an account timezone/last_ip country mismatch or
        #   - an email address with a farmable domain
        if owner_details.is_user? && owner_details.account_age_in_days < 14
          if owner_details.time_zone_mismatched?
            return TrustTiers::TierResult.new(UNTRUSTED, TierResult::MISMATCHED_TIMEZONE)
          end

          if owner_details.has_farmable_email_domain?
            return TrustTiers::TierResult.new(UNTRUSTED, TierResult::FARMABLE_DOMAIN)
          end
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner created more than 30 days ago
        if owner_details.oldest_owner_older_than_neutral_free_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::OLDEST_OWNER_AGE)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful, including IAP)
        if owner_details.has_paid_money_or_iap? && !owner_details.last_payment_failed? && owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
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
        science("trust_tiers.calculate_tier_v_two") do |e|
          e.use do
            calculate_tier_v2_control(owner, owner_details, force_calculation: force_calculation)
          end

          e.try do
            calculate_tier_v2_candidate(owner, owner_details, force_calculation: force_calculation)
          end

          e.after_run do |result|
            control_result = result.control.value
            candidate_result = result.candidates.first&.value

            if candidate_result.nil?
              GitHub.logger.info(
                "Trust tier calculation error - candidate is nil",
                "code.namespace":   self.class.name,
                "code.function":    "calculate_tier",
                "gh.owner.id":      owner.id
              )
              next
            end

            mismatch = control_result != candidate_result

            # Record metrics to datadog for every case where the experiment ran, so we can determine
            # the percentage of requests that will classify accounts in different tiers.
            GitHub.dogstats.increment("trust_tiers.tier_calculation_result", tags: [
              "version:v2",
              "mismatch:#{mismatch}",
              "control_tier:#{control_result.tier}",
              "control_reason:#{control_result.reason}",
              "candidate_tier:#{candidate_result.tier}",
              "candidate_reason:#{candidate_result.reason}"
            ])

            # Also log details about individual mismatches to Splunk for further analysis.
            if mismatch
              GitHub.logger.info(
                "Trust tier calculation mismatch",
                "code.namespace":   self.class.name,
                "code.function":    "calculate_tier_v2",
                "gh.owner.id":      owner.id,
                "control_tier":     control_result.tier,
                "control_reason":   control_result.reason,
                "candidate_tier":   candidate_result.tier,
                "candidate_reason": candidate_result.reason
              )
            end

            Hydro::PublishRetrier.publish(
              {
                control_trust_tier: control_result.tier,
                candidate_trust_tier: candidate_result.tier,
                control_reason: control_result.reason.to_s,
                candidate_reason: candidate_result.reason.to_s,
                mismatch: mismatch,
                database_id: owner.id,
                global_relay_id: owner.global_relay_id,
                entity_type: owner.class.name,
                experiment_name: "trust_tiers.calculate_tier_v_two",
              },
              schema: "github.trust_tier_science.v0.TrustTierScience",
              partition_key: owner.id,
              topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
            )
          end
        end
      end

      def calculate_tier_v2_control(owner, owner_details, force_calculation: false)
        # for stafftools, we will pass in the force_calculation flag to see what the tier WOULD have been
        unless force_calculation
          forced_tier = forced_tier_for_owner(owner)

          if forced_tier > 0
            return TrustTiers::TierResult.new(forced_tier, TierResult::SETTINGS_FORCED)
          end
        end

        # **************** TRUSTED ****************
        # * Current or former sales serve accounts (invoiced Organization or invoiced Enterprise)
        if owner.invoiced? || owner.was_invoiced?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::BUSINESS_OR_INVOICED)
        end

        # **************** UNTRUSTED ****************
        # * Accounts with billing disputes/chargebacks
        if owner_details.has_disputes?
          return TrustTiers::TierResult.new(UNTRUSTED, TierResult::DISPUTED_ACCOUNT)
        end

        # **************** TRUSTED ****************
        # * Accounts with established billing history (including IAP)
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        if !owner_details.last_payment_failed? && owner_details.has_established_billing_history_or_iap?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::ESTABLISHED_BILLING)
        end

        # **************** TRUSTED ****************
        # * Oldest account owner > 14 days old AND has eligible coupon
        if owner_details.has_eligible_coupon? && owner_details.oldest_owner_older_than_trusted_couponed_age_limit?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::TRUSTED_COUPON)
        end

        # **** NOT QUITE READY FOR NEUTRAL YET ****
        # New-ish account with:
        #   - an account timezone/last_ip country mismatch or
        #   - an email address with a farmable domain
        if owner_details.is_user? && owner_details.account_age_in_days < 14
          if owner_details.time_zone_mismatched?
            return TrustTiers::TierResult.new(UNTRUSTED, TierResult::MISMATCHED_TIMEZONE)
          end

          if owner_details.has_farmable_email_domain?
            return TrustTiers::TierResult.new(UNTRUSTED, TierResult::FARMABLE_DOMAIN)
          end
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner created more than 30 days ago
        if owner_details.oldest_owner_older_than_neutral_free_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::OLDEST_OWNER_AGE)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful, including IAP)
        if owner_details.has_paid_money_or_iap? && !owner_details.last_payment_failed? && owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
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

      # Candidate: uses experimental behavior we want to audit with Scientist
      def calculate_tier_v2_candidate(owner, owner_details, force_calculation: false)
        # for stafftools, we will pass in the force_calculation flag to see what the tier WOULD have been
        unless force_calculation
          forced_tier = forced_tier_for_owner(owner)

          if forced_tier > 0
            return TrustTiers::TierResult.new(forced_tier, TierResult::SETTINGS_FORCED)
          end
        end

        # **************** TRUSTED ****************
        # * Current or former sales serve accounts (invoiced Organization or invoiced Enterprise)
        if owner.invoiced? || owner.was_invoiced?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::BUSINESS_OR_INVOICED)
        end

        # **************** UNTRUSTED ****************
        # * Accounts with billing disputes/chargebacks
        if owner_details.has_disputes?
          return TrustTiers::TierResult.new(UNTRUSTED, TierResult::DISPUTED_ACCOUNT)
        end

        # **************** TRUSTED ****************
        # * Accounts with established billing history (including IAP)
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        if !owner_details.last_payment_failed? && owner_details.has_established_billing_history_or_iap?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::ESTABLISHED_BILLING)
        end

        # **************** TRUSTED ****************
        # * Orgs/businesses with established billing history whose last payment failed (lapsed payment grace)
        if owner.feature_flag_enabled_or_raise?(:trust_tier_org_lapse_grace) && owner_details.eligible_for_lapsed_payment_grace? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          return TrustTiers::TierResult.new(TRUSTED, TierResult::ESTABLISHED_BILLING_LAPSED_PAYMENT)
        end

        # **************** TRUSTED ****************
        # * Oldest account owner > 14 days old AND has eligible coupon
        if owner_details.has_eligible_coupon? && owner_details.oldest_owner_older_than_trusted_couponed_age_limit?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::TRUSTED_COUPON)
        end

        # **************** TRUSTED ****************
        # * Azure-metered orgs/enterprises with at least $100 of billed usage older than
        #   60 days. Azure billing produces no GitHub payment history, so established billing
        #   history never matches; instead we trust substantial aged Azure usage.
        if owner_details.is_azure_metered_with_billed_usage?
          return TrustTiers::TierResult.new(TRUSTED, TierResult::AZURE_METERED_BILLING)
        end

        # **** NOT QUITE READY FOR NEUTRAL YET ****
        # New-ish account with:
        #   - an account timezone/last_ip country mismatch or
        #   - an email address with a farmable domain
        if owner_details.is_user? && owner_details.account_age_in_days < 14
          if owner_details.time_zone_mismatched?
            return TrustTiers::TierResult.new(UNTRUSTED, TierResult::MISMATCHED_TIMEZONE)
          end

          if owner_details.has_farmable_email_domain?
            return TrustTiers::TierResult.new(UNTRUSTED, TierResult::FARMABLE_DOMAIN)
          end
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner created more than 30 days ago
        if owner_details.oldest_owner_older_than_neutral_free_age_limit?
          return TrustTiers::TierResult.new(NEUTRAL, TierResult::OLDEST_OWNER_AGE)
        end

        # **************** NEUTRAL ****************
        # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful, including IAP)
        if owner_details.has_paid_money_or_iap? && !owner_details.last_payment_failed? && owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
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

      def forced_tier_for_owner(owner)
        if owner.is_a?(Business)
          TrustTiers::BusinessOverride.get(owner)
        else
          owner.settings.get(:trust_tier)
        end
      end

      def log_calculation_results(owner, owner_details, calculated_tier, client_name, fn, v2_tier_difference: 0, former_calculated_tier: nil, former_tier_reason: nil)
        GitHub.dogstats.increment("trust_tiers.calculate_tier_result", tags: [
          "client_name:#{client_name}",
          "calculated_tier:#{calculated_tier.tier}",
          "tier_reason:#{calculated_tier.reason}",
          "former_calculated_tier:#{former_calculated_tier}",
          "former_tier_reason:#{former_tier_reason}",
          "v2_tier_difference:#{v2_tier_difference}",
        ])

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
