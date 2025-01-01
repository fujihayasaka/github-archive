# typed: strict
# frozen_string_literal: true

module Copilot
  module Authorization
    class AccessLoader
      include GitHub::Memoizer

      FREE_ACCESS_TYPES = T.let(%i[
        COMPLIMENTARY_ACCESS
        COMPLIMENTARY_ACCESS_QUOTA
        FREE_EDUCATIONAL
        FREE_EDUCATIONAL_QUOTA
        FREE_ENGAGED_OSS
        FREE_ENGAGED_OSS_QUOTA
        FREE_FACULTY
        FREE_FACULTY_QUOTA
        FREE_GITHUB_STAR
        FREE_GITHUB_STAR_QUOTA
        FREE_MS_MVP
        FREE_MS_MVP_QUOTA
        FREE_Y_COMBINATOR
        FREE_Y_COMBINATOR_QUOTA
        HEY_GITHUB
        HEY_GITHUB_QUOTA
        OTHER_FREE_ACCESS
        WORKSHOP
      ], T::Array[Symbol])

      CFB_ACCESS_TYPES = T.let(%i[
        COPILOT_FOR_BUSINESS_SEAT
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_MULTI_QUOTA
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_QUOTA
        COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA
        COPILOT_FOR_BUSINESS_SEAT_QUOTA
        COPILOT_FOR_BUSINESS_TRIAL_SEAT
        COPILOT_FOR_BUSINESS_TRIAL_SEAT_QUOTA
        COPILOT_STANDALONE_SEAT
        COPILOT_STANDALONE_SEAT_ASSIGNMENT
        COPILOT_STANDALONE_SEAT_ASSIGNMENT_MULTI_QUOTA
        COPILOT_STANDALONE_SEAT_ASSIGNMENT_QUOTA
        COPILOT_STANDALONE_SEAT_MULTI_QUOTA
        COPILOT_STANDALONE_SEAT_QUOTA
        COPILOT_STANDALONE_TRIAL_SEAT
        COPILOT_STANDALONE_TRIAL_SEAT_QUOTA
      ], T::Array[Symbol])

      CFB_TRIAL_ACCESS_TYPES = T.let(%i[
        COPILOT_FOR_BUSINESS_TRIAL_SEAT
        COPILOT_FOR_BUSINESS_TRIAL_SEAT_QUOTA
        COPILOT_STANDALONE_TRIAL_SEAT
        COPILOT_STANDALONE_TRIAL_SEAT_QUOTA
      ], T::Array[Symbol])

      CFE_ACCESS_TYPES = T.let(%i[
        COPILOT_ENTERPRISE_SEAT
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT_MULTI_QUOTA
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT_QUOTA
        COPILOT_ENTERPRISE_SEAT_MULTI_QUOTA
        COPILOT_ENTERPRISE_SEAT_QUOTA
        COPILOT_ENTERPRISE_TRIAL_SEAT
        COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF
        COPILOT_ENTERPRISE_TRIAL_SEAT_QUOTA
      ], T::Array[Symbol])

      CFE_TRIAL_ACCESS_TYPES = T.let(%i[
        COPILOT_ENTERPRISE_TRIAL_SEAT
        COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF
        COPILOT_ENTERPRISE_TRIAL_SEAT_QUOTA
      ], T::Array[Symbol])

      MULTI_ACCESS_TYPES = T.let(%i[
        COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_MULTI_QUOTA
        COPILOT_ENTERPRISE_SEAT_MULTI_QUOTA
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT_MULTI_QUOTA
        COPILOT_STANDALONE_SEAT_MULTI_QUOTA
        COPILOT_STANDALONE_SEAT_ASSIGNMENT_MULTI_QUOTA
      ], T::Array[Symbol])

      PAID_ACCESS_TYPES = T.let(%i[
        COPILOT_ENTERPRISE_SEAT
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT_MULTI_QUOTA
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT_QUOTA
        COPILOT_ENTERPRISE_SEAT_MULTI_QUOTA
        COPILOT_ENTERPRISE_SEAT_QUOTA
        COPILOT_FOR_BUSINESS_SEAT
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_MULTI_QUOTA
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_QUOTA
        COPILOT_FOR_BUSINESS_SEAT_MULTI_QUOTA
        COPILOT_FOR_BUSINESS_SEAT_QUOTA
        COPILOT_STANDALONE_SEAT
        COPILOT_STANDALONE_SEAT_ASSIGNMENT
        COPILOT_STANDALONE_SEAT_ASSIGNMENT_MULTI_QUOTA
        COPILOT_STANDALONE_SEAT_ASSIGNMENT_QUOTA
        COPILOT_STANDALONE_SEAT_MULTI_QUOTA
        COPILOT_STANDALONE_SEAT_QUOTA
        MAX_MONTHLY_SUBSCRIBER_QUOTA
        MAX_YEARLY_SUBSCRIBER_QUOTA
        MONTHLY_SUBSCRIBER
        MONTHLY_SUBSCRIBER_QUOTA
        PLUS_MONTHLY_SUBSCRIBER_QUOTA
        PLUS_YEARLY_SUBSCRIBER_QUOTA
        TRIAL_30_MONTHLY_SUBSCRIBER_QUOTA
        TRIAL_30_YEARLY_SUBSCRIBER_QUOTA
        YEARLY_SUBSCRIBER
        YEARLY_SUBSCRIBER_QUOTA
      ], T::Array[Symbol])

      LIMITED_ACCESS_TYPES = T.let(%i[
        FREE_LIMITED_COPILOT
      ], T::Array[Symbol])

      SKIP_SNIPPY_CHECK_TYPES = T.let(%i[
        CODESPACES_DEMO
        PARTNER_ACCESS
      ] + CFB_ACCESS_TYPES + CFE_ACCESS_TYPES, T::Array[Symbol])

      BLOCKED_ACCESS_TYPES = T.let(%i[
        BILLING_LOCKED
        CODESPACES_DEMO_INACTIVE
        COPILOT_FOR_BUSINESS_BILLING_LOCKED
        ENTERPRISE_MANAGED
        EXPIRED_COUPON
        FEATURE_FLAG_BLOCKED
        GO_HTTP_CLIENT
        NO_ACCESS
        PROGRAMMATIC_TOKEN_GENERATION
        REVOKED_COUPON
        SPAMMY_USER
        SUBSCRIPTION_ENDED
        TRADE_RESTRICTED
        TRADE_RESTRICTED_COUNTRY
        ACCESS_REVOKED
        UNKNOWN
      ], T::Array[Symbol])

      ALL_TYPES = T.let((
        BLOCKED_ACCESS_TYPES +
        CFB_ACCESS_TYPES +
        CFE_ACCESS_TYPES +
        FREE_ACCESS_TYPES +
        MULTI_ACCESS_TYPES +
        PAID_ACCESS_TYPES +
        SKIP_SNIPPY_CHECK_TYPES
      ).uniq, T::Array[Symbol])

      CFI_PRO_ACCESS_TYPES = T.let(%i[
        MONTHLY_SUBSCRIBER
        YEARLY_SUBSCRIBER
        TRIAL_30_MONTHLY_SUBSCRIBER
        TRIAL_30_YEARLY_SUBSCRIBER
        MONTHLY_SUBSCRIBER_QUOTA
        YEARLY_SUBSCRIBER_QUOTA
      ], T::Array[Symbol])

      CFI_PRO_PLUS_ACCESS_TYPES = T.let(%i[
        FREE_GITHUB_STAR
        FREE_GITHUB_STAR_QUOTA
        FREE_MS_MVP
        FREE_MS_MVP_QUOTA
        PLUS_MONTHLY_SUBSCRIBER_QUOTA
        PLUS_YEARLY_SUBSCRIBER_QUOTA
        WORKSHOP
      ], T::Array[Symbol])

      CFI_MAX_ACCESS_TYPES = T.let(%i[
        MAX_MONTHLY_SUBSCRIBER_QUOTA
        MAX_YEARLY_SUBSCRIBER_QUOTA
      ], T::Array[Symbol])

      CI_VERBOSE_REASONS = T.let({
        # this does not have a consumptive version
        "codespaces_demo" => "Codespaces Demo",
        # this isn't really real (it's just used for the demo above)
        "codespaces_demo_inactive" => "Codespaces Demo Inactive",
        # this is a CI PRO user that gets copilot for free for some reason
        # don't read that wrong - we want them to have it (we gave it to them)
        # but we don't know what that reason is HERE in the code
        "complimentary_access" => "Complimentary Access",
        "complimentary_access_quota" => "Complimentary Access (Consumptive)",
        # these users have an educational coupon granting them CI Pro access
        "free_educational" => "Free Educational User",
        "free_educational_quota" => "Free Educational User (Consumptive)",
        # these users maintain open source projects and get copilot for free
        "free_engaged_oss" => "Free Open Source Maintainer",
        "free_engaged_oss_quota" => "Free Open Source Maintainer (Consumptive)",
        # these users have a faculty coupon granting them CI Pro access
        "free_faculty" => "Free Faculty",
        "free_faculty_quota" => "Free Faculty (Consumptive)",
        # these users are members of the github stars org and get copilot for free
        # (see developer relations)
        "free_github_star" => "Free GitHub Star",
        "free_github_star_quota" => "Free GitHub Star (Consumptive)",
        # these are the free users who have a monthly limit
        # they always have a quota so we don't have to say it and make them feel bad
        "free_limited_copilot" => "Copilot Free",
        # these are ms mvps (they have a coupon)  (see developer relations)
        "free_ms_mvp" => "Free Microsoft MVP",
        "free_ms_mvp_quota" => "Free Microsoft MVP (Consumptive)",
        # these users are part of y combinator and have a special deal (see developer relations)
        "free_y_combinator" => "Free Y Combinator",
        "free_y_combinator_quota" => "Free Y Combinator (Consumptive)",
        # these folks were part of the hey github beta program and they get copilot for free for life
        "hey_github" => "Hey, GitHub",
        "hey_github_quota" => "Hey, GitHub (Consumptive)",
        # these users are part of some workshop happening sometime
        "workshop" => "Workshop",
        "workshop_quota" => "Workshop (Consumptive)",

        # these people give us money cause they are nice
        "monthly_subscriber" => "Monthly Subscriber",
        "monthly_subscriber_quota" => "Monthly Subscriber (Consumptive)",
        "yearly_subscriber" => "Yearly Subscriber",
        "yearly_subscriber_quota" => "Yearly Subscriber (Consumptive)",
        "trial_30_monthly_subscriber" => "30 Day Trial Monthly Subscriber",
        "trial_30_monthly_subscriber_quota" => "30 Day Trial Monthly Subscriber (Consumptive)",
        "trial_30_yearly_subscriber" => "30 Day Trial Yearly Subscriber",
        "trial_30_yearly_subscriber_quota" => "30 Day Trial Yearly Subscriber (Consumptive)",

        # this is the new pro plus sku
        "plus_monthly_subscriber_quota" => "Plus Monthly Subscriber (Consumptive)",
        "plus_yearly_subscriber_quota" => "Plus Yearly Subscriber (Consumptive)",
        "trial_30_plus_monthly_subscriber_quota" => "30 Day Trial Plus Monthly Subscriber (Consumptive)",
        "trial_30_plus_yearly_subscriber_quota" => "30 Day Trial Plus Yearly Subscriber (Consumptive)",

        # Max SKU strings
        "max_monthly_subscriber_quota" => "Max Monthly Subscriber (Consumptive)",
        "max_yearly_subscriber_quota" => "Max Yearly Subscriber (Consumptive)",

        # these following are deprecated but kept here for completeness
        "codespaces_demo_period" => "Codespaces Demo Period",
        "other_free_access" => "Other Free Access",
        "partner_access" => "Partner Access",
        "technical_preview_extension" => "Technical Preview Extension",
      }, T::Hash[String, String])

      CB_VERBOSE_REASONS = T.let({
        # copilot business
        "copilot_for_business_seat_assignment" => "Copilot for Business Seat",
        "copilot_for_business_seat_assignment_quota" => "Copilot for Business Seat (Consumptive)",
        "copilot_for_business_seat" => "Copilot for Business Seat",
        "copilot_for_business_seat_quota" => "Copilot for Business Seat (Consumptive)",
        "copilot_for_business_trial_seat" => "Copilot for Business Trial Seat",
        "copilot_for_business_trial_seat_quota" => "Copilot for Business Trial Seat (Consumptive)",
      }, T::Hash[String, String])

      CE_VERBOSE_REASONS = T.let({
        # copilot enterprise
        "copilot_enterprise_seat" => "Copilot Enterprise Seat",
        "copilot_enterprise_seat_quota" => "Copilot Enterprise Seat (Consumptive)",
        "copilot_enterprise_seat_assignment" => "Copilot Enterprise Seat",
        "copilot_enterprise_seat_assignment_quota" => "Copilot Enterprise Seat (Consumptive)",
        "copilot_enterprise_trial_seat" => "Copilot Enterprise Trial Seat",
        "copilot_enterprise_trial_seat_quota" => "Copilot Enterprise Trial Seat (Consumptive)",
        "copilot_enterprise_trial_seat_staff" => "Copilot Enterprise Trial Seat (Sales Serve non-consmptive)",
      }, T::Hash[String, String])

      CS_VERBOSE_REASONS = T.let({
        # copilot standalone
        "copilot_standalone_seat" => "Copilot Standalone Seat",
        "copilot_standalone_seat_quota" => "Copilot Standalone Seat (Consumptive)",
        "copilot_standalone_seat_assignment" => "Copilot Standalone Seat",
        "copilot_standalone_seat_assignment_quota" => "Copilot Standalone Seat (Consumptive)",
        "copilot_standalone_trial_seat" => "Copilot Standalone Trial Seat",
        "copilot_standalone_trial_seat_quota" => "Copilot Standalone Trial Seat (Consumptive)",
      }, T::Hash[String, String])

      MULTI_VERBOSE_REASONS = T.let({
        "copilot_for_business_seat_multi_quota" => "Copilot for Business Seat (Consumptive)",
        "copilot_for_business_seat_assignment_multi_quota" => "Copilot for Business Seat (Consumptive)",
        "copilot_enterprise_seat_multi_quota" => "Copilot Enterprise Seat (Consumptive)",
        "copilot_enterprise_seat_assignment_multi_quota" => "Copilot Enterprise Seat (Consumptive)",
        "copilot_standalone_seat_multi_quota" => "Copilot Standalone Seat (Consumptive)",
        "copilot_standalone_seat_assignment_multi_quota" => "Copilot Standalone Seat (Consumptive)",
      }, T::Hash[String, String])

      OTHER_REASONS = T.let({
        "access_revoked" => "Access Revoked",
        "billing_locked" => "Billing Locked",
        "copilot_for_business_billing_locked" => "Copilot Seat Owner Billing Locked",
        "enterprise_managed" =>  "Enterprise Managed User",
        "expired_coupon" => "Expired Coupon",
        "feature_flag_blocked" => "Administrative Block",
        "go_http_client" => "Go HTTP Client",
        "no_access" => "No Access",
        "programmatic_token_generation" => "Programmatic Token Generation",
        "revoked_coupon" => "Revoked Coupon",
        "spammy_user" => "Spammy User",
        "subscription_ended" => "Subscription Ended",
        "trade_restricted_country" => "Trade Restricted Country",
        "trade_restricted" => "Trade Restricted",
        "unknown" => "Unknown",
      }, T::Hash[String, String])

      VERBOSE_REASONS = T.let(
        CI_VERBOSE_REASONS.merge(CB_VERBOSE_REASONS).merge(CE_VERBOSE_REASONS).merge(CS_VERBOSE_REASONS).merge(MULTI_VERBOSE_REASONS).merge(OTHER_REASONS),
        T::Hash[String, String],
      )

      sig { returns(Symbol) }
      attr_accessor :type

      alias to_sym type

      sig { params(copilot_user: Copilot::User, type: Symbol, include_snippy: T::Boolean).void }
      def initialize(copilot_user, type, include_snippy)
        @copilot_user   = copilot_user
        @type           = type
        @include_snippy = include_snippy
        @evaluated      = T.let(false, T::Boolean)
      end

      sig { params(type: Symbol).void }
      def set_type(type)
        @type = type
        @evaluated = true
      end

      sig { returns(T::Boolean) }
      memoize def allowed?
        # if we haven't evaluated or we have and the type is blocked, let's say no
        return false if @type == :NOT_EVALUATED || BLOCKED_ACCESS_TYPES.include?(@type)
        # we don't need to evaluate snippy if we can skip it or we're not including it (stafftools)
        return true if SKIP_SNIPPY_CHECK_TYPES.include?(@type) || !@include_snippy

        # if we're not blocked and we're not skipping snippy, let's evaluate it
        unless @copilot_user.public_code_suggestions_configured?
          @type = :SNIPPY_NOT_CONFIGURED
          return false
        end

        # if we are a free limited user, we will always return a 200
        if has_limited_access?
          # we need to check if we have any completions quota remaining
          if !@copilot_user.has_completions_quota_remaining? && !@copilot_user.has_chat_quota_remaining?
            GitHub.dogstats.increment("copilot.free_over_limits")
            GitHub.logger.info("Free user over limits", "gh.user.id": @copilot_user.id)
          end
        end

        true
      rescue StandardError => e # rubocop:todo Lint/RescueException
        Copilot::ErrorReporter.report!(Copilot::Errors::AccessCheckError.from_error(e), copilot_user: @copilot_user)
        false
      end

      sig { returns(String) }
      def verbose_reason
        return "Snippy Unconfigured" if @type == :SNIPPY_NOT_CONFIGURED

        key = @type.to_s.downcase
        if VERBOSE_REASONS.key?(key)
          VERBOSE_REASONS[key].to_s
        else
          GitHub.dogstats.increment("copilot.access_result.#{@type}")
          "Unknown"
        end
      end

      sig { returns(T::Boolean) }
      def has_premium_interactions?
        # this will return false for copilot free users
        # even though they are TECHNICALLY consumptive, but
        # they can't do premium interactions
        return false if has_limited_access?

        @type.end_with?("_QUOTA")
      end

      sig { returns(T::Boolean) }
      def has_paid_access?
        PAID_ACCESS_TYPES.include?(@type)
      end

      sig { returns(T::Boolean) }
      def has_cfb_access?
        CFB_ACCESS_TYPES.include?(@type) || has_cfe_access?
      end

      sig { returns(T::Boolean) }
      def has_cfb_trial_access?
        CFB_TRIAL_ACCESS_TYPES.include?(@type)
      end

      sig { returns(T::Boolean) }
      def has_multi_access?
        MULTI_ACCESS_TYPES.include?(@type)
      end

      sig { returns(T::Boolean) }
      def has_cfe_trial_access?
        CFE_TRIAL_ACCESS_TYPES.include?(@type)
      end

      sig { returns(T::Boolean) }
      def has_cfe_access?
        CFE_ACCESS_TYPES.include?(@type)
      end

      sig { returns(T::Boolean) }
      def has_limited_access?
        LIMITED_ACCESS_TYPES.include?(@type)
      end

      sig { returns(T::Boolean) }
      def has_pro_access?
        CFI_PRO_ACCESS_TYPES.include?(@type)
      end

      # This method defines whether the user has access to the self-signed cert proxy thing (https://github.com/github/copilot-foundations/issues/547)
      # This is based on whether they are a member of an organization that is using Copilot for Business
      # We may change the criteria in the future
      alias has_ssc? has_cfb_access?

      sig { returns(T::Boolean) }
      def has_cfi_access?
        return false if @type == :NOT_EVALUATED || BLOCKED_ACCESS_TYPES.include?(@type)

        !has_cfb_access? && !has_cfe_access?
      end

      sig { returns(T::Boolean) }
      def has_pro_plus_access?
        has_cfi_access? && CFI_PRO_PLUS_ACCESS_TYPES.include?(@type)
      end

      sig { returns(T::Boolean) }
      def has_max_access?
        has_cfi_access? && CFI_MAX_ACCESS_TYPES.include?(@type)
      end
    end
  end
end
