# typed: strict
# frozen_string_literal: true

module Copilot
  class Authorizer
    extend T::Helpers

    include GitHub::Memoizer

    sig { returns(Copilot::Authorization::AccessLoader) }
    attr_reader :access_loader

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { returns(Symbol) }
    attr_reader :subscription_type

    delegate :user_object, to: :copilot_user
    delegate :has_paid_access?, :has_cfb_access?, :has_cfb_trial_access?, :has_cfi_access?,
             :has_cfe_access?, :has_cfe_trial_access?, :verbose_reason, :has_ssc?, :has_limited_access?, :has_pro_plus_access?,
             :has_pro_access?, :has_max_access?, :has_premium_interactions?, :has_multi_access?, to: :access_loader

    BILLING_CHECK_BLOCKED_TYPES = T.let([:SUBSCRIPTION_ENDED, :BILLING_LOCKED], T::Array[Symbol])

    sig do
      params(
        copilot_user: Copilot::User,
        context: T.nilable(Context),
        env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        include_snippy: T::Boolean
      ).void
    end
    def initialize(copilot_user, context = nil, env = {}, include_snippy: true)
      @copilot_user   = copilot_user
      @context        = context
      @env            = T.let(env.with_indifferent_access, T::Hash[T.untyped, T.untyped]) # rubocop:disable Sorbet/ForbidTUntyped

      @user_agent            = T.let(@env.fetch("user_agent", ""), String)
      @editor_version        = T.let(@env.fetch("editor_version", ""), String)
      @editor_plugin_version = T.let(@env.fetch("editor_plugin_version", ""), String)

      @include_snippy = include_snippy

      @subscription_type = T.let(:UNKNOWN, Symbol)

      @user_object = T.let(@copilot_user.user_object, ::User)

      @restrictor = T.let(
        Copilot::Authorization::TradeRestrictor.new(@copilot_user),
        Copilot::Authorization::TradeRestrictor,
      )
      @access_loader = T.let(
        Copilot::Authorization::AccessLoader.new(
          copilot_user,
          :NOT_EVALUATED,
          @include_snippy
        ),
        Copilot::Authorization::AccessLoader,
      )
      @seat_assignments = T.let([], T::Array[Copilot::SeatAssignment])

      if @editor_version.blank? && @editor_plugin_version.blank? && @user_agent.present?
        lowercase_user_agent = @user_agent.downcase
        # this means that they are programmatically generating requests.
        #  has "go-http" or user_agent has "go-resty"
        if lowercase_user_agent.starts_with?("go-http-client") || lowercase_user_agent.starts_with?("go-resty")
          log("User is blocked because of programmatic Go client", { "gh.user_agent" => @user_agent })
          @access_loader.set_type(:GO_HTTP_CLIENT)
          return
        end

        # Python/3.12 aiohttp/3.11.11
        if @user_object.feature_flag_enabled_or_raise?(:copilot_block_python_user_agent) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          if lowercase_user_agent.starts_with?("python") || lowercase_user_agent.include?("aiohttp")
            log("User is blocked because of programmatic mitmproxy client", { "gh.user_agent" => @user_agent })
            @access_loader.set_type(:PROGRAMMATIC_TOKEN_GENERATION)
            return
          end
        end
      end

      # if the caller doesn't pass context, we can't do any restricting.
      # if you're blocked geographically we don't want to even look up your information
      if @context.present? && @restrictor.restricted?(@context, @env)
        GitHub.dogstats.increment("copilot.access_result.ip_blocked")
        @access_loader.set_type(@restrictor.restriction_type)
      else
        # let's start loading up some stuff
        value = async_access_type.sync
        @access_loader.set_type(value)
      end
    end

    sig { returns(String) }
    def reason
      @access_loader.type.to_s.downcase
    end

    sig { returns(T::Array[Copilot::Organization]) }
    memoize def organizations
      @copilot_user.copilot_organizations.uniq
    end

    sig { returns(T::Array[String]) }
    def organization_list
      organizations.collect(&:analytics_tracking_id)
    end

    sig { returns(T::Array[String]) }
    def organization_login_list
      organizations.collect(&:display_login)
    end

    sig { returns(T::Boolean) }
    def access_allowed?
      @access_loader.allowed?
    end

    sig { returns(Symbol) }
    def access_type
      @access_loader.type
    end

    sig { returns(String) }
    def access_type_sku
      access_type.to_s.downcase
    end

    sig { returns(Promise[String]) }
    def async_access_type_sku
      async_access_type.then do |access_type|
        next access_type.to_s.downcase
      end
    end

    # Asynchronously determine the access type for this user
    sig { returns(Promise[Symbol]) }
    def async_access_type
      GitHub.logger.with_named_tags("code.function" => "async_access_type", "code.namespace" => self.class.name) do
        GitHub.tracer.in_span("copilot.authorizer.async_access_type") do |_span|
          log("Determining access type")
          promise = Promise.new

          ###############################################################################################
          # 🚨 THE ORDER OF THESE CHECKS MATTERS, DO NOT CHANGE THEM UNLESS YOU KNOW WHAT YOU'RE DOING 🚨
          ###############################################################################################

          # We want to check the feature flags first because they should be relatively cheap
          # Also, if someone is feature flag blocked, we don't want to check anything else
          async_properties_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          # Then, we want to check whether the user is a free user, free meaning has a Copilot::LimitedUser record,
          # which allows to use Copilot, with a quota, with no subscription or payment method
          # For now only returns :FREE_LIMITED_COPILOT and :NOT_EVALUATED
          has_free_limited = T.let(false, T::Boolean)
          async_limited_user_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            has_free_limited = access_type == :FREE_LIMITED_COPILOT
          end

          # Despite what this check is called, this is a check for whether the user has COMPLIMENTARY ACCESS,
          # AKA they have a Copilot::FreeUser record.
          async_free_user_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          # Then, we check whether the user subscribes monthly or yearly to one of the other copilot plans,
          # these are Pro, Pro+, and Max as of this comment; any INDIVIDUAL plan which has a SubscriptionItem
          async_billing_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            if access_type != :NOT_EVALUATED
              # we'll defer returning these blocked types until after we check for a seat or seat assignment
              # by fulfilling the promise with @subscription_type below if applicable
              @subscription_type = access_type
              return promise.fulfill(access_type) unless BILLING_CHECK_BLOCKED_TYPES.include?(access_type)
            end
          end

          all_seat_assignments_revoked = T.let(false, T::Boolean)
          # Now we check whether the user has any Copilot::SeatAssignments, and if they all have access_revoked_at set,
          # we would defer the return :ACCESS_REVOKED, which is a BLOCKED_TYPE in the access loader.
          # 🚨 This check has to occur BEFORE the seats check
          async_seat_assignments_revoked_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            all_seat_assignments_revoked = access_type == :ACCESS_REVOKED
          end

          # Now we check for any Copilot::Seats and if any exist, we return the appropriate SKU as the access type
          async_seats_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end unless all_seat_assignments_revoked

          # We will only fall through to here and return an actual SKU if the user only has seat assignments
          # that are not associated with seats which are not already pending cancellation, this is EXTREMELY RARE,
          # and should only happen within the cooldown period.
          async_seat_assignments_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end unless all_seat_assignments_revoked

          # this is for a codespace demo user
          async_codespaces_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          # We want limited user licenses to be returned only if there are no other paid access available
          promise.fulfill(:FREE_LIMITED_COPILOT) if has_free_limited

          # below this point are promises that would only return an access_type that is in BLOCKED_ACCESS_TYPES
          promise.fulfill(:ACCESS_REVOKED) if all_seat_assignments_revoked

          # We want to defer fulfilling blocked types for the billing check until after we check for seats and seat assignments
          promise.fulfill(@subscription_type) if BILLING_CHECK_BLOCKED_TYPES.include?(@subscription_type)

          # We need to block access for EMUs who somehow got here
          promise.fulfill(:ENTERPRISE_MANAGED) if @user_object.is_enterprise_managed?

          # we check for any expired or revoked coupons so that we can return an access type and show a
          # meaningful editor notification
          async_expired_coupon_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          # catchall
          promise.fulfill(:NO_ACCESS)
        end
      end
    end

    sig { returns(Promise[GitHub::Result]) }
    def async_seat_assignments_revoked_check
      GitHub.logger.with_named_tags(
        "code.function" => "async_seat_assignments_revoked_check",
        "gh.user.id" => copilot_user.user_object.id
      ) do
        GitHub.logger.info("Loading seat assignments for user")
        GitHub.tracer.in_span("copilot.authorizer.async_seat_assignments_revoked_check") do
          result = GitHub::Result.new do
            GitHub.dogstats.distribution_time("copilot.authorizer.async_seat_assignments_revoked_check.latency") do
              @seat_assignments = copilot_user.async_revokable_seat_assignments.sync

              if @seat_assignments.any?
                if @seat_assignments.all?(&:access_revoked?)
                  log("All seat assignments for user have their access revoked.", { "gh.user.id" => copilot_user.id })
                  GitHub.dogstats.increment("copilot.authorizer.async_seat_assignments_revoked_check.access_revoked")

                  # This means async_access_type will return access_revoked and allowed? will return false in the AccessLoader
                  increment_access_type(:ACCESS_REVOKED)
                else
                  :NOT_EVALUATED
                end
              else
                :NOT_EVALUATED
              end
            end
          end
          Promise.new.fulfill(result)
        end
      end
    end

    # This checks the spammy and feature flag blocked properties of the user
    # These should be relatively cheap and they filter out anyone who is blocked
    sig { returns(Promise[GitHub::Result]) }
    def async_properties_check
      GitHub.logger.with_named_tags("code.function" => "async_properties_check") do
        GitHub.tracer.in_span("copilot.authorizer.async_properties_check") do |_span|
          result = GitHub::Result.new do
            # Let's check if this user is spammy and get out of here if they are
            if copilot_user.spammy?
              log("User is spammy", { "gh.user.spammy" => true })
              increment_access_type(:SPAMMY_USER)
            # Let's check if this user is a partner user and get out of here if they are
            elsif copilot_user.is_partner_user?
              log("User is partner user", { "gh.copilot.partner_user" => true })
              increment_access_type(:PARTNER_ACCESS)
            # Let's check if this user was blocked by ff and get out of here if they are
            elsif copilot_user.administrative_blocked?
              log("User is administrative blocked", { "gh.copilot.administrative_blocked" => true })
              increment_access_type(:FEATURE_FLAG_BLOCKED) # TODO: Make this ADMINISTRATIVE_BLOCKED
            else
              GitHub.dogstats.increment("copilot.authorizer.async_properties_check.no_match")
              log("No match for properties check")
              :NOT_EVALUATED
            end
          end
          Promise.new.fulfill(result)
        end
      end
    end

    sig { returns(Promise[GitHub::Result]) }
    def async_free_user_check
      GitHub.logger.with_named_tags("code.function" => "async_free_user_check") do
        GitHub.tracer.in_span("copilot.authorizer.async_free_user_check") do |_span|
          result = GitHub::Result.new do
            quota_enabled = user_object.feature_flag_enabled_or_raise?(:copilot_individual_quota) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            free_user = Copilot::FreeUser.find_by(user_id: @user_object.id)
            if free_user.present? && free_user.subscribed?
              handle_free_user_type(free_user, quota_enabled)
            else
              GitHub.dogstats.increment("copilot.authorizer.async_free_user_check.no_match")
              log("No match for free user check")
              :NOT_EVALUATED
            end
          end
          Promise.new.fulfill(result)
        end
      end
    end

    sig { returns(Promise[GitHub::Result]) }
    def async_limited_user_check
      GitHub.logger.with_named_tags("code.function" => "async_limited_user_check") do
        GitHub.tracer.in_span("copilot.authorizer.async_limited_user_check") do |_span|
          result = GitHub::Result.new do
            log("Free limited flag set")
            # the feature flag is set, so we need to look up the Copilot::LimitedUser for this user
            limited_user = Copilot::LimitedUser.find_by(user_id: @user_object.id)

            if limited_user.present? && limited_user.subscribed?
              GitHub.dogstats.increment("copilot.authorizer.async_limited_user_check.match")
              log("Match for free limited copilot check", { "gh.copilot.limited_user_subscribed_at" => limited_user.subscribed_at.to_s })
              increment_access_type(:FREE_LIMITED_COPILOT)
            else
              GitHub.dogstats.increment("copilot.authorizer.async_limited_user_check.no_match")
              log("No match for free limited copilot check", { "gh.copilot.limited_user_exists" => limited_user.present? })
              :NOT_EVALUATED
            end
          end
          Promise.new.fulfill(result)
        end
      end
    end

    sig { returns(Promise[GitHub::Result]) }
    def async_codespaces_check
      GitHub.logger.with_named_tags("code.function" => "async_codespaces_check") do
        GitHub.tracer.in_span("copilot.authorizer.async_codespaces_check") do |_span|
          result = GitHub::Result.new do
            # let's see if this user is a codespaces demo user
            if copilot_user.codespaces_demo_request_allowed?
              # we were so naive when we were young - thinking that a feature flag would be enough
              # we now have a 120 minute-ish timeout, so we have to check that here
              # increment the session
              copilot_user.increment_codespaces_demo_session_value!

              if copilot_user.codespaces_demo_session_active?
                # this means that the session value after incrementing isn't the FINAL VALUE
                log("User is Codespaces demo user with an active session", { "gh.copilot.codespaces_demo_session_active" => true })
                increment_access_type(:CODESPACES_DEMO)
              else
                # IT'S THE FINAL COUNTDOWN
                log("User is Codespaces demo user, but their session is not active", { "gh.copilot.codespaces_demo_session_active" => false })
                increment_access_type(:CODESPACES_DEMO_INACTIVE)
              end
            else
              log("User is not Codespaces demo user")
              GitHub.dogstats.increment("copilot.authorizer.async_codespaces_check.no_match")
              :NOT_EVALUATED
            end
          end
          Promise.new.fulfill(result)
        end
      end
    end

    # |                                      | BusinessTrial | Configuration | Organization | Business |
    # |--------------------------------------|---------------|---------------|--------------|----------|
    # | COPILOT_ENTERPRISE_TRIAL_SEAT        | ENTERPRISE    | BUSINESS      | REQUIRED     | REQUIRED |
    # | COPILOT_FOR_BUSINESS_TRIAL_SEAT      | BUSINESS      | BUSINESS      | REQUIRED     | OPTIONAL |
    # | COPILOT_STANDALONE_SEAT              | NONE          | BUSINESS      | NONE         | REQUIRED |
    # | COPILOT_ENTERPRISE_SEAT              | NONE          | ENTERPRISE    | REQUIRED     | REQUIRED |
    # | COPILOT_FOR_BUSINESS_SEAT            | NONE          | BUSINESS      | REQUIRED     | OPTIONAL |
    sig { returns(Promise[GitHub::Result]) }
    def async_seats_check
      GitHub.logger.with_named_tags("code.function" => "async_seats_check") do
        GitHub.tracer.in_span("copilot.authorizer.async_seats_check") do |_span|
          result = GitHub::Result.new do
            # let's see if this user has a Copilot::Seat record assigned to them
            seats = Copilot::Seat.where(assigned_user_id: @user_object.id)

            if seats.any?
              # this user has at least one Copilot::Seat record, so we need to prefill the copilot_sku association for the seats
              GitHub::PrefillAssociations.prefill_batch_method(seats, :copilot_sku)
              GitHub::PrefillAssociations.prefill_batch_method(seats, :customer_ids)

              # load up all of the plans for this user's seats
              copilot_skus = seats.map(&:copilot_sku)
              customer_ids = seats.map(&:customer_ids).compact
              multi = customer_ids.length > 1 && @user_object.feature_flag_enabled_or_raise?(:copilot_multi_quota) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

              log("User has at least one seat", { "gh.copilot.seats.count" => seats.count })

              # it's possible that the user has multiple seats, so we need to check all of them
              # we want to return the highest access type that we find
              # COPILOT_ENTERPRISE_TRIAL_SEAT then COPILOT_FOR_BUSINESS_TRIAL_SEAT then COPILOT_STANDALONE_SEAT
              # then COPILOT_ENTERPRISE_SEAT then COPILOT_FOR_BUSINESS_SEAT

              if @user_object.feature_flag_enabled?(:copilot_access_trial_reorder, default: false)
                # |                                      | BusinessTrial | Configuration | Organization | Business |
                # |--------------------------------------|---------------|---------------|--------------|----------|
                # | COPILOT_ENTERPRISE_TRIAL_SEAT        | ENTERPRISE    | BUSINESS      | REQUIRED     | REQUIRED |
                # | COPILOT_ENTERPRISE_SEAT              | NONE          | ENTERPRISE    | REQUIRED     | REQUIRED |
                # | COPILOT_FOR_BUSINESS_TRIAL_SEAT      | BUSINESS      | BUSINESS      | REQUIRED     | OPTIONAL |
                # | COPILOT_FOR_BUSINESS_SEAT            | NONE          | BUSINESS      | REQUIRED     | OPTIONAL |
                # | COPILOT_STANDALONE_SEAT              | NONE          | BUSINESS      | NONE         | REQUIRED |
                if copilot_skus.all?(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
                  increment_access_type(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
                elsif copilot_skus.include?(:COPILOT_ENTERPRISE_TRIAL_SEAT) || copilot_skus.include?(:COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF)
                  quota = @user_object.feature_flag_enabled_or_raise?(:copilot_enterprise_quota) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                  quota = false if copilot_skus.include?(:COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF)
                  increment_access_type(:COPILOT_ENTERPRISE_TRIAL_SEAT, quota_enabled: quota)
                elsif copilot_skus.include?(:COPILOT_ENTERPRISE_SEAT)
                  increment_access_type(:COPILOT_ENTERPRISE_SEAT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_enterprise_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                elsif copilot_skus.include?(:COPILOT_FOR_BUSINESS_TRIAL_SEAT)
                  increment_access_type(:COPILOT_FOR_BUSINESS_TRIAL_SEAT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_business_quota)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                elsif copilot_skus.include?(:COPILOT_FOR_BUSINESS_SEAT)
                  increment_access_type(:COPILOT_FOR_BUSINESS_SEAT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_business_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                elsif copilot_skus.include?(:COPILOT_STANDALONE_SEAT)
                  increment_access_type(:COPILOT_STANDALONE_SEAT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_standalone_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                else
                  log("User has no match for seat check")
                  GitHub.dogstats.increment("copilot.authorizer.async_seats_check.no_match")
                  :NOT_EVALUATED
                end
              else
                if copilot_skus.all?(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
                  increment_access_type(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
                elsif copilot_skus.include?(:COPILOT_ENTERPRISE_TRIAL_SEAT) || copilot_skus.include?(:COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF)
                  quota = @user_object.feature_flag_enabled_or_raise?(:copilot_enterprise_quota) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                  quota = false if copilot_skus.include?(:COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF)
                  increment_access_type(:COPILOT_ENTERPRISE_TRIAL_SEAT, quota_enabled: quota)
                elsif copilot_skus.include?(:COPILOT_FOR_BUSINESS_TRIAL_SEAT)
                  increment_access_type(:COPILOT_FOR_BUSINESS_TRIAL_SEAT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_business_quota)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                elsif copilot_skus.include?(:COPILOT_STANDALONE_SEAT)
                  increment_access_type(:COPILOT_STANDALONE_SEAT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_standalone_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                elsif copilot_skus.include?(:COPILOT_ENTERPRISE_SEAT)
                  increment_access_type(:COPILOT_ENTERPRISE_SEAT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_enterprise_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                elsif copilot_skus.include?(:COPILOT_FOR_BUSINESS_SEAT)
                  increment_access_type(:COPILOT_FOR_BUSINESS_SEAT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_business_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                else
                  log("User has no match for seat check")
                  GitHub.dogstats.increment("copilot.authorizer.async_seats_check.no_match")
                  :NOT_EVALUATED
                end
              end
            else
              log("User does not have a seat")
              GitHub.dogstats.increment("copilot.authorizer.async_seats_check.no_match")
              :NOT_EVALUATED
            end
          end
          Promise.new.fulfill(result)
        end
      end
    end

    # |                                      | Configuration | Organization | Business |
    # |--------------------------------------|---------------|--------------|----------|
    # | COPILOT_ENTERPRISE_SEAT_ASSIGNMENT   | ENTERPRISE    | REQUIRED     | REQUIRED |
    # | COPILOT_STANDALONE_SEAT_ASSIGNMENT   | BUSINESS      | NONE         | REQUIRED |
    # | COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT | BUSINESS      | REQUIRED     | OPTIONAL |
    sig { returns(Promise[GitHub::Result]) }
    def async_seat_assignments_check
      GitHub.logger.with_named_tags("code.function" => "async_seat_assignments_check") do
        GitHub.tracer.in_span("copilot.authorizer.async_seat_assignments_check") do |_span|
          result = GitHub::Result.new do
            # Use the preloaded assignments. This shouldn't happen but if the checks get moved it is theoretically
            # possible that the assignments would never be loaded.
            assignments = copilot_user.async_seat_assignments.sync

            if assignments.any?
              # this user has at least one Copilot::SeatAssignment record, so we need to prefill the copilot_sku association for the assignments
              GitHub::PrefillAssociations.prefill_batch_method(assignments, :copilot_sku)
              GitHub::PrefillAssociations.prefill_batch_method(assignments, :customer_ids)

              copilot_skus = assignments.map(&:copilot_sku)
              customer_ids = assignments.map(&:customer_ids)
              multi = customer_ids.length > 1 && @user_object.feature_flag_enabled_or_raise?(:copilot_multi_quota) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

              log("User has at least one seat assignment", { "gh.copilot.seat_assignments.count" => assignments.count })

              # it's possible that the user has multiple seat assignments, so we need to check all of them
              # we want to return the highest access type that we find
              # COPILOT_STANDALONE_SEAT_ASSIGNMENT then COPILOT_ENTERPRISE_SEAT_ASSIGNMENT then COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT
              if copilot_skus.all?(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
                increment_access_type(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
              elsif copilot_skus.include?(:COPILOT_STANDALONE_SEAT_ASSIGNMENT)
                increment_access_type(:COPILOT_STANDALONE_SEAT_ASSIGNMENT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_standalone_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              elsif copilot_skus.include?(:COPILOT_ENTERPRISE_SEAT_ASSIGNMENT)
                increment_access_type(:COPILOT_ENTERPRISE_SEAT_ASSIGNMENT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_enterprise_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              elsif copilot_skus.include?(:COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT)
                increment_access_type(:COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT, quota_enabled: @user_object.feature_flag_enabled_or_raise?(:copilot_business_quota), multi: multi) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              else
                log("User has no match for seat assignment check")
                GitHub.dogstats.increment("copilot.authorizer.async_seat_assignments_check.no_match")
                :NOT_EVALUATED
              end
            else
              log("User does not have any seat assignments")
              GitHub.dogstats.increment("copilot.authorizer.async_seat_assignments_check.no_match")
              :NOT_EVALUATED
            end
          end
          Promise.new.fulfill(result)
        end
      end
    end

    sig { returns(Promise[GitHub::Result]) }
    def async_billing_check
      GitHub.logger.with_named_tags("code.function" => "async_billing_check") do
        GitHub.tracer.in_span("copilot.authorizer.async_billing_check") do |_span|
          if copilot_user.disabled?
            log("User is disabled")
            Promise.new.fulfill(GitHub::Result.new { :BILLING_LOCKED })
          else
            result = GitHub::Result.new do
              subscription = StringIO.new

              # load up copilot product uuids
              subscribables = ::Billing::ProductUUID.where(product_type: Copilot::PRODUCT_TYPE, product_key: Copilot::INDIVIDUAL_PRODUCT_KEYS)

              # get user's plan subscription
              plan_subscription = ::Billing::PlanSubscription.where(user_id: user_object.id)
              # get user's subscription items for copilot product uuids
              subscription_items = ::Billing::SubscriptionItem.where(
                plan_subscription: plan_subscription,
                subscribable: subscribables,
              )

              if subscription_items.any?
                # see if we have any active
                active_subscription_items = subscription_items.select do |subscription_item|
                  subscription_item.quantity > 0
                end

                if active_subscription_items.any?
                  copilot_active_subscription_item = T.must(active_subscription_items.first)
                  on_free_trial = copilot_active_subscription_item.free_trial_ends_on.present? && GitHub::Billing.future?(copilot_active_subscription_item.free_trial_ends_on + 1.day)
                  subscribable = subscribables.find { |item| item.id == copilot_active_subscription_item.subscribable_id }
                  pro_plus = subscribable&.product_key == Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY
                  max = subscribable&.product_key == Copilot::INDIVIDUAL_MAX_PRODUCT_KEY
                  interval = subscribable&.billing_cycle.to_sym
                  if on_free_trial
                    subscription << "TRIAL_30_"
                  end

                  if pro_plus
                    subscription << "PLUS_"
                  end

                  if max
                    subscription << "MAX_"
                  end

                  if interval == :month
                    subscription << "MONTHLY"
                  elsif interval == :year
                    subscription << "YEARLY"
                  end

                  subscription << "_SUBSCRIBER"

                  # pro plus and max are always subject to consumption quotas.
                  # however, we will also be rolling out quota to all Copilot Individual Users on 5/5
                  # all CB/CE users who pay via CC on 5/12
                  # and the rest on 5/19
                  # since this is an individual only lookup, let's check the individual quota feature flag
                  if pro_plus || max || user_object.feature_flag_enabled_or_raise?(:copilot_individual_quota) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                    subscription << "_QUOTA"
                  end

                  increment_access_type(subscription.string.to_sym)
                else
                  :SUBSCRIPTION_ENDED
                end
              else
                :NOT_EVALUATED
              end
            end
            Promise.new.fulfill(result)
          end
        end
      end
    end

    sig { returns(Promise[GitHub::Result]) }
    def async_expired_coupon_check
      GitHub.logger.with_named_tags("code.function" => "async_expired_coupon_check") do
        GitHub.tracer.in_span("copilot.authorizer.async_expired_coupon_check") do |_span|
          result = GitHub::Result.new do
            reason = :NOT_EVALUATED
            # load up all of the coupon redemptions for this user (including revoked and expired)
            # we are doing this after all of the other checks to see if the reason is a bad coupon
            CouponRedemption.for_user(user_object.id).each do |redemption|
              coupon = redemption.coupon
              if coupon.present? && coupon.code == "revoked"
                reason = :REVOKED_COUPON
                break
              end

              if redemption.expired?
                reason = :EXPIRED_COUPON
              end
            end
            reason
          end
          Promise.new.fulfill(result)
        end
      end
    end

    sig { params(free_user: Copilot::FreeUser, quota_enabled: T::Boolean).returns(Symbol) }
    def handle_free_user_type(free_user, quota_enabled)
      log("User is free user", free_user.to_otel)
      case free_user.type
      when ::Copilot::FreeUser::ENGAGED_OSS
        increment_access_type(:FREE_ENGAGED_OSS, quota_enabled:)
      when ::Copilot::FreeUser::EDUCATIONAL
        increment_access_type(:FREE_EDUCATIONAL, quota_enabled:)
      when ::Copilot::FreeUser::FACULTY
        increment_access_type(:FREE_FACULTY, quota_enabled:)
      when ::Copilot::FreeUser::GITHUB_STAR
        increment_access_type(:FREE_GITHUB_STAR, quota_enabled:)
      when ::Copilot::FreeUser::MS_MVP
        increment_access_type(:FREE_MS_MVP, quota_enabled:)
      when ::Copilot::FreeUser::Y_COMBINATOR
        increment_access_type(:FREE_Y_COMBINATOR, quota_enabled:)
      when ::Copilot::FreeUser::COMPLIMENTARY_ACCESS
        increment_access_type(:COMPLIMENTARY_ACCESS, quota_enabled:)
      when ::Copilot::FreeUser::HEY_GITHUB
        increment_access_type(:HEY_GITHUB, quota_enabled:)
      when ::Copilot::FreeUser::TECHNICAL_PREVIEW_EXTENSION
        increment_access_type(:TECHNICAL_PREVIEW_EXTENSION, quota_enabled:)
      when ::Copilot::FreeUser::WORKSHOP
        increment_access_type(:WORKSHOP, quota_enabled: false)
      else
        increment_access_type(:OTHER_FREE_ACCESS, quota_enabled:)
      end
    end

    sig { params(access_type: Symbol, quota_enabled: T::Boolean, multi: T::Boolean).returns(Symbol) }
    def increment_access_type(access_type, quota_enabled: false, multi: false)
      if quota_enabled
        # multi only matters for quota enabled access types
        access_type = "#{access_type}_MULTI" if multi
        access_type = "#{access_type}_QUOTA".to_sym
      end

      GitHub.dogstats.increment("copilot.authorizer.access_type.#{access_type.to_s.downcase}")
      log("User has access type #{access_type.to_s.downcase}", { "gh.copilot.access_type" => access_type.to_s.downcase })

      access_type
    end

    sig { params(message: String, attributes: T::Hash[String, T.untyped]).void } # rubocop:disable Sorbet/ForbidTUntyped
    def log(message, attributes = {})
      span = GitHub.current_span
      attributes.each do |key, val|
        span.set_attribute(key, val)
      end

      span.add_event(message)
      GitHub.logger.info(
        message,
        {
          "gh.user.dunning" => @copilot_user.dunning?,
          "gh.user.spammy" => @copilot_user.spammy?,
          "gh.copilot.administrative_blocked" => @copilot_user.administrative_blocked?,
          "gh.copilot.editor_version" => @editor_version,
          "gh.copilot.editor_plugin_version" => @editor_plugin_version,
          "gh.copilot.user_agent" => @user_agent,
        }.merge(attributes),
      )
    end
  end
end
