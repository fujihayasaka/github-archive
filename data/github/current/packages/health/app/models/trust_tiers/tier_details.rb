# typed: true
# frozen_string_literal: true

module TrustTiers
  class TierDetails
    TRUSTED_COUPONED_AGE_LIMIT = 14.days
    NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT = 3.days
    NEUTRAL_FREE_AGE_LIMIT = 30.days
    BILLING_HISTORY_MATURATION_PERIOD = 2.months

    # Borrowed from SpamSlam via
    # https://github.com/github/spam-slam/blob/8bf428e48260a1fa3957d7e13da849a241dec740/pkg/kusto/queries.go#L59
    FARMABLE_EMAIL_DOMAINS = %w(
      foxmail yeah gmail googlemail hotmail outlook live msn aol yahoo icloud proton protonmail qq
      126 163 fastmail yandex zoho mail zohomail tutamail universidadisep int ancashpropiedades
      privaterelay isrc 52it nlfree kigege oaifree uuidhy axiba 4branding atomicmail onet tukiunge
      wiwsjambok 88 sina 139 naver vip aliyun freemail altmail lanchong 52shizhan rainaki megumin
      dingtalk ariskapi oklyr himarra krseller
    )

    # Azure-metered accounts produce no GitHub-side payment history, so they never reach
    # TRUSTED via established billing history. We treat substantial *aged* billed usage
    # emitted through Azure as a trust signal: Billing already locks Azure subscriptions that
    # go DISABLED for fraud/non-payment, and requiring the usage to be older than MIN_AGE
    # avoids trusting recently accrued usage that could still be charged back.
    # See github/hosted-compute#3236.
    AZURE_METERED_BILLED_USAGE_MIN_AGE = 60.days
    AZURE_METERED_BILLED_USAGE_MAX_LOOKBACK_MONTHS = 6
    AZURE_METERED_BILLED_USAGE_THRESHOLD_CENTS = 100_00 # $100

    attr_reader :account

    def initialize(account)
      @account = account
      @coupon = account.coupon unless is_business?
    end

    # Checks if the account has an eligible coupon present.
    # For Pro (aka "Developer") accounts, eligible coupons are non-education coupons.
    # For non-Pro accounts, all coupons are eligible, including education coupons.
    # @return [Boolean]
    def has_eligible_coupon?
      return @has_eligible_coupon if defined?(@has_eligible_coupon)
      return @has_eligible_coupon = @coupon.present? && !@coupon.education_coupon? if @account.plan.pro?
      @has_eligible_coupon = @coupon.present?
    end

    # this replaces the call to the SpamChecker.has_actually_paid_money method
    # that function returns true if they've paid money at ANY time in the past.
    # we need more precision - we want to verify that they have paid money twice:
    #  $ once in the current billing cycle
    #  $ once at least BILLING_HISTORY_MATURATION_PERIOD ago
    def has_established_billing_history?
      return @has_established_billing_history if defined?(@has_established_billing_history)

      # if they haven't paid money, short-circuit before the extra history check here
      @has_established_billing_history = has_paid_money? && GitHub::SpamChecker.billing_success_in_period(account, 50.years.ago, BILLING_HISTORY_MATURATION_PERIOD.ago)
    end

    def has_paid_money?
      return @has_paid_money if defined?(@has_paid_money)

      # treating businesses like invoiced accounts here and returning true for them; consider adding that case into has_actually_paid_money
      @has_paid_money = is_business? || GitHub::SpamChecker.has_actually_paid_money?(@account)
    end

    # Include IAP (Apple/Google) subscription as a fallback
    # for accounts that pay through in-app purchase rather than traditional billing.
    def has_paid_money_or_iap?
      return @has_paid_money_or_iap if defined?(@has_paid_money_or_iap)

      @has_paid_money_or_iap = has_paid_money? || has_in_app_purchase?
    end

    # Include mature IAP subscription as an alternative
    # to established billing history through traditional billing transactions.
    def has_established_billing_history_or_iap?
      return @has_established_billing_history_or_iap if defined?(@has_established_billing_history_or_iap)

      @has_established_billing_history_or_iap = has_established_billing_history? || has_mature_in_app_purchase?
    end

    def has_trial?
      return @has_trial if defined?(@has_trial)

      if @account.plan.business_plus?
        trial = @account.github_plan_trial
        return @has_trial = trial.present? && trial.active?
      end

      @has_trial = false
    end

    def is_paid_plan?
      return @is_paid_plan if defined?(@is_paid_plan)

      # if the plan is a business plus plan (lowercase e-nterprise), check if it's a trial
      if @account.plan.business_plus?
        trial = @account.github_plan_trial
        return @is_paid_plan = !trial.present?
      end

      @is_paid_plan = @account.plan.paid?
    end

    def last_payment_failed?
      return @last_payment_failed if defined?(@last_payment_failed)

      @last_payment_failed = !is_business? && @account.dunning?
    end

    def oldest_owner_older_than_trusted_couponed_age_limit?
      return @oldest_owner_older_than_trusted_couponed_age_limit if defined?(@oldest_owner_older_than_trusted_couponed_age_limit)

      # A handful of orgs seem to not have an associated admin, so we ignore orgs without one for this check
      @oldest_owner_older_than_trusted_couponed_age_limit = oldest_owner_age.present? && oldest_owner_age < TRUSTED_COUPONED_AGE_LIMIT.ago
    end

    def oldest_owner_older_than_neutral_free_age_limit?
      return @oldest_owner_older_than_neutral_free_age_limit if defined?(@oldest_owner_older_than_neutral_free_age_limit)

      # A handful of orgs seem to not have an associated admin, so we ignore orgs without one for this check
      @oldest_owner_older_than_neutral_free_age_limit = oldest_owner_age.present? && oldest_owner_age < NEUTRAL_FREE_AGE_LIMIT.ago
    end

    def oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
      return @oldest_owner_older_than_neutral_paid_or_couponed_age_limit if defined?(@oldest_owner_older_than_neutral_paid_or_couponed_age_limit)

      # A handful of orgs seem to not have an associated admin, so we ignore orgs without one for this check
      @oldest_owner_older_than_neutral_paid_or_couponed_age_limit = oldest_owner_age.present? && oldest_owner_age < NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago
    end

    def oldest_owner_age
      return @oldest_owner_age if defined?(@oldest_owner_age)

      @oldest_owner_age = oldest_owner&.created_at
    end

    def oldest_owner
      return @oldest_owner if defined?(@oldest_owner)

      admins = @account.admins

      if admins.is_a?(ActiveRecord::Relation)
        @oldest_owner = admins.order(:created_at).first
      else
        @oldest_owner = admins.sort_by(&:created_at).first
      end

      @oldest_owner
    end

    def account_age_in_days
      return @account_age_in_days if defined?(@account_age_in_days)

      @account_age_in_days = @account.created_at ? (Time.current - @account.created_at).to_i / 86400 : 0
    end

    def is_business?
      return @is_a_business if defined?(@is_a_business)

      @is_a_business = @account.is_a?(Business)
    end

    def eligible_for_lapsed_payment_grace?
      return @eligible_for_lapsed_payment_grace if defined?(@eligible_for_lapsed_payment_grace)

      @eligible_for_lapsed_payment_grace = last_payment_failed? && has_established_billing_history? && (is_business? || @account.is_a?(Organization))
    end

    def is_user?
      return @is_a_user if defined?(@is_a_user)

      @is_a_user = @account.user?
    end

    def time_zone_mismatched?
      return @time_zone_mismatched if defined?(@time_zone_mismatched)

      @time_zone_mismatched = if timezone_and_domain_checks_enabled? && @account.time_zone.present? && @account.last_ip.present?
        !time_zones_for_target_country.include?(@account.time_zone)
      else
        false
      end
    end

    def has_farmable_email_domain?
      return @has_farmable_email_domain if defined?(@has_farmable_email_domain)

      @has_farmable_email_domain = if !timezone_and_domain_checks_enabled?
        false
      else
        @account.emails.any? do |user_email|
          domain = user_email.email.split("@")&.last&.downcase
          domain_without_tld = domain.sub(/\.[^.]+\Z/, "")
          domain_without_tld.in?(FARMABLE_EMAIL_DOMAINS)
        end
      end
    end

    def has_disputes?
      return @has_disputes if defined?(@has_disputes)

      @has_disputes = if @account.respond_to?(:billing_disputes) && dispute_checks_enabled?
        @account.billing_disputes.exists?
      else
        false
      end
    end

    def azure_metered_account?
      !@account.user? &&
        !has_established_billing_history? &&
        @account.respond_to?(:metered_via_azure) && @account.metered_via_azure?
    end

    def is_azure_metered_with_billed_usage?
      return @has_azure_metered_aged_billed_usage if defined?(@has_azure_metered_aged_billed_usage)

      @has_azure_metered_aged_billed_usage = if FeatureFlag.vexi.enabled?(:trust_tiers_azure_metered_billing_upgrade, @account, default: false)
        azure_metered_account? && azure_metered_has_aged_billed_usage?
      else
        false
      end
    end

    private

    def iap_billing_history_enabled?
      FeatureFlag.vexi.enabled?(:trust_tiers_iap_billing_history, @account, default: false)
    end

    def has_in_app_purchase?
      return @has_in_app_purchase if defined?(@has_in_app_purchase)

      @has_in_app_purchase = if !iap_billing_history_enabled?
        false
      elsif !@account.business? && @account.bot?
        false
      else
        GitHub.dogstats.time("trust_tiers.has_in_app_purchase") do
          sub_item_ids = ::Billing::SubscriptionItem.for_account(@account).active.pluck(:id)
          next false if sub_item_ids.empty?

          ::Billing::AppleSubscription.where(subscription_item_id: sub_item_ids).exists? ||
            ::Billing::GoogleSubscription.where(subscription_item_id: sub_item_ids).exists?
        end
      end
    end

    def has_mature_in_app_purchase?
      return @has_mature_in_app_purchase if defined?(@has_mature_in_app_purchase)

      @has_mature_in_app_purchase = if !iap_billing_history_enabled?
        false
      elsif !@account.business? && @account.bot?
        false
      else
        GitHub.dogstats.time("trust_tiers.has_mature_in_app_purchase") do
          sub_item_ids = ::Billing::SubscriptionItem.for_account(@account).active
            .where(created_at: 50.years.ago..BILLING_HISTORY_MATURATION_PERIOD.ago)
            .pluck(:id)
          next false if sub_item_ids.empty?

          ::Billing::AppleSubscription.where(subscription_item_id: sub_item_ids).exists? ||
            ::Billing::GoogleSubscription.where(subscription_item_id: sub_item_ids).exists?
        end
      end
    end

    def timezone_and_domain_checks_enabled?
      FeatureFlag.vexi.enabled?(:trust_tiers_timezone_domain_checks, @account, default: false)
    end

    def dispute_checks_enabled?
      FeatureFlag.vexi.enabled?(:trust_tier_dispute_checks, @account, default: false)
    end

    def time_zones_for_target_country
      return [] unless target_country = target_country_from_last_ip

      begin
        ActiveSupport::TimeZone.country_zones(target_country)
      rescue TZInfo::InvalidCountryCode
        []
      end
    end

    def target_country_from_last_ip
      return nil unless ip_address = @account.last_ip
      return nil unless ip_info = GitHub::Location.look_up(ip_address)
      ip_info[:country]
    end

    # Returns true when an azure metered account has accrued at least
    # AZURE_METERED_BILLED_USAGE_THRESHOLD_CENTS of billed usage in months that are entirely
    # older than AZURE_METERED_BILLED_USAGE_MIN_AGE. Starting from the most recent fully-aged
    # month, we walk backwards a month at a time (up to AZURE_METERED_BILLED_USAGE_MAX_LOOKBACK_MONTHS)
    # accumulating billed usage and stop as soon as the running total reaches the threshold. We
    # also stop early if we hit a fully-aged month with no billed usage, since an inactive month
    # implies older months are unlikely to be useful. Requiring the usage to be aged avoids
    # trusting recently accrued usage that could still be charged back. Emits a timing metric for
    # the lookup and logs how many months were examined. Defensive against billing API
    # errors/timeouts: any failure returns false so trust tier calculation never raises.
    def azure_metered_has_aged_billed_usage?
      customer = @account.try(:customer)
      return false if customer.nil?

      billing_client = Billing::Platform::Api::Client.new
      # Most recent month entirely older than MIN_AGE: the month containing the cutoff still
      # holds some sub-MIN_AGE usage, so step back one further month.
      month = (Time.current.in_billing_timezone - AZURE_METERED_BILLED_USAGE_MIN_AGE).beginning_of_month.prev_month

      total_cents = 0
      months_examined = 0
      threshold_met = T.let(false, T::Boolean)
      stopped_on_zero_usage_month = T.let(false, T::Boolean)

      started_at = GitHub::Dogstats.monotonic_time
      begin
        AZURE_METERED_BILLED_USAGE_MAX_LOOKBACK_MONTHS.times do
          months_examined += 1
          response = billing_client.get_usage_total(
            usage_entity_id: customer.id,
            year: month.year,
            month: month.month
          )
          break if response.is_a?(Billing::Platform::Api::Error)

          cents = Billing::Money.parse(response[:billableAmount].to_f).cents
          total_cents += cents
          if total_cents >= AZURE_METERED_BILLED_USAGE_THRESHOLD_CENTS
            threshold_met = true
            break
          end

          # A fully-aged month with no billed usage implies the customer was inactive, so
          # looking further back is unlikely to be useful. Stop early to avoid extra calls.
          if cents.zero?
            stopped_on_zero_usage_month = true
            break
          end

          month = month.prev_month
        end
      ensure
        GitHub.dogstats.distribution(
          "trust_tiers.azure_metered_billed_usage_lookup",
          GitHub::Dogstats.duration(started_at, GitHub::Dogstats.monotonic_time),
          tags: [
            "months_examined:#{months_examined}",
            "threshold_met:#{threshold_met}"
          ]
        )
      end

      GitHub.dogstats.distribution("trust_tiers.azure_metered_billed_usage_months_examined", months_examined)
      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => "azure_metered_has_aged_billed_usage?",
        "gh.catalog_service" => "github/trust_tiers",
        "gh.owner.database_id" => @account.id,
        "gh.trust_tiers.azure_metered_billed_usage_months_examined" => months_examined,
        "gh.trust_tiers.azure_metered_billed_usage_threshold_met" => threshold_met,
        "gh.trust_tiers.azure_metered_billed_usage_stopped_on_zero_usage_month" => stopped_on_zero_usage_month
      )

      threshold_met
    rescue => e
      Failbot.report(e)
      false
    end
  end
end
