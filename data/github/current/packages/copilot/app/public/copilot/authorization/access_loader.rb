# typed: strict
# frozen_string_literal: true

module Copilot
  module Authorization
    class AccessLoader
      include GitHub::Memoizer
      extend T::Sig

      FREE_ACCESS_TYPES = T.let(%i[
        COMPLIMENTARY_ACCESS
        FREE_EDUCATIONAL
        FREE_ENGAGED_OSS
        FREE_FACULTY
        FREE_GITHUB_STAR
        FREE_MS_MVP
        FREE_Y_COMBINATOR
        HEY_GITHUB
        OTHER_FREE_ACCESS
        TECHNICAL_PREVIEW_EXTENSION
        WORKSHOP
      ], T::Array[Symbol])

      CFB_ACCESS_TYPES = T.let(%i[
        COPILOT_FOR_BUSINESS_SEAT
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT
        COPILOT_FOR_BUSINESS_TRIAL_SEAT
        COPILOT_STANDALONE_SEAT
        COPILOT_STANDALONE_SEAT_ASSIGNMENT
        COPILOT_STANDALONE_TRIAL_SEAT
      ], T::Array[Symbol])

      CFE_ACCESS_TYPES = T.let(%i[
        COPILOT_ENTERPRISE_SEAT
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT
        COPILOT_ENTERPRISE_TRIAL_SEAT
      ], T::Array[Symbol])

      PAID_ACCESS_TYPES = T.let(%i[
        COPILOT_ENTERPRISE_SEAT
        COPILOT_ENTERPRISE_SEAT_ASSIGNMENT
        COPILOT_FOR_BUSINESS_SEAT
        COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT
        COPILOT_STANDALONE_SEAT
        COPILOT_STANDALONE_SEAT_ASSIGNMENT
        MONTHLY_SUBSCRIBER
        YEARLY_SUBSCRIBER
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
        REVOKED_COUPON
        SPAMMY_USER
        SUBSCRIPTION_ENDED
        TRADE_RESTRICTED
        TRADE_RESTRICTED_COUNTRY
        UNKNOWN
      ], T::Array[Symbol])

      ALL_TYPES = T.let((
        BLOCKED_ACCESS_TYPES +
        CFB_ACCESS_TYPES +
        CFE_ACCESS_TYPES +
        FREE_ACCESS_TYPES +
        PAID_ACCESS_TYPES +
        SKIP_SNIPPY_CHECK_TYPES
      ).uniq, T::Array[Symbol])

      VERBOSE_REASONS = T.let({
        "billing_locked" => "Billing Locked",
        "codespaces_demo" => "Codespaces Demo",
        "codespaces_demo_inactive" => "Codespaces Demo Inactive",
        "complimentary_access" => "Complimentary Access",
        "copilot_enterprise_seat" => "Copilot Enterprise Seat",
        "copilot_enterprise_seat_assignment" => "Copilot Enterprise Seat",
        "copilot_enterprise_trial_seat" => "Copilot Enterprise Trial Seat",
        "copilot_for_business_billing_locked" => "Copilot Seat Owner Billing Locked",
        "copilot_for_business_seat_assignment" => "Copilot for Business Seat",
        "copilot_for_business_seat" => "Copilot for Business Seat",
        "copilot_for_business_trial_seat" => "Copilot for Business Trial Seat",
        "copilot_standalone_seat" => "Copilot Standalone Seat",
        "copilot_standalone_seat_assignment" => "Copilot Standalone Seat",
        "copilot_standalone_trial_seat" => "Copilot Standalone Trial Seat",
        "educational" => "Free Educational User",
        "engagedoss" => "Free Open Source Maintainer",
        "enterprise_managed" =>  "Enterprise Managed User",
        "expired_coupon" => "Expired Coupon",
        "faculty" => "Free Faculty",
        "feature_flag_blocked" => "Administrative Block",
        "free_educational" => "Free Educational User",
        "free_engaged_oss" => "Free Open Source Maintainer",
        "free_enterprise_trial" => "Enterprise Trial User",
        "free_enterprise" => "Enterprise User",
        "free_faculty" => "Free Faculty",
        "free_github_star" => "Free GitHub Star",
        "free_ms_mvp" => "Free Microsoft MVP",
        "free_y_combinator" => "Free Y Combinator",
        "github_star" => "Free GitHub Star",
        "go_http_client" => "Go HTTP Client",
        "hey_github" => "Hey, GitHub",
        "monthly_subscriber" => "Monthly Subscriber",
        "ms_mvp" => "Free Microsoft MVP",
        "no_access" => "No Access",
        "other_free_access" => "Other Free Access",
        "partner_access" => "Partner Access",
        "revoked_coupon" => "Revoked Coupon",
        "spammy_user" => "Spammy User",
        "subscription_ended" => "Subscription Ended",
        "technical_preview_extension" => "Technical Preview Extension",
        "trade_restricted_country" => "Trade Restricted Country",
        "trade_restricted" => "Trade Restricted",
        "trial_30_monthly_subscriber" => "30 Day Trial Monthly Subscriber",
        "trial_30_yearly_subscriber" => "30 Day Trial Yearly Subscriber",
        "trial_monthly_subscriber" => "Trial Monthly Subscriber",
        "trial_yearly_subscriber" => "Trial Yearly Subscriber",
        "workshop" => "Workshop",
        "unknown" => "Unknown",
        "y_combinator" => "Free Y Combinator",
        "yearly_subscriber" => "Yearly Subscriber",
      }, T::Hash[String, String])

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
        true
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
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
      def has_paid_access?
        PAID_ACCESS_TYPES.include?(@type)
      end

      sig { returns(T::Boolean) }
      def has_cfb_access?
        CFB_ACCESS_TYPES.include?(@type) || has_cfe_access?
      end

      sig { returns(T::Boolean) }
      def has_cfe_access?
        CFE_ACCESS_TYPES.include?(@type)
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
    end
  end
end
