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
    delegate :has_paid_access?, :has_cfb_access?, :has_cfb_trial_access?, :has_cfi_access?, :has_cfe_access?, :has_cfe_trial_access?, :verbose_reason, :has_ssc?, :has_limited_access?, to: :access_loader

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
        # this means that they are programmatically generating requests.
        if @user_object.feature_enabled?(:copilot_block_go_client)
          #  has "go-http" or user_agent has "go-resty"
          if @user_agent.starts_with?("Go-http-client") || @user_agent.starts_with?("go-resty")
            log("User is blocked because of programmatic Go client", { "gh.user_agent" => @user_agent })
            @access_loader.set_type(:GO_HTTP_CLIENT)
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

          # We want to check the feature flags first because they should be relatively cheap
          # Also, if someone is feature flag blocked, we don't want to check anything else
          async_properties_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          # This is first because FREE_EDUCATIONAL is still top 5 in access types
          async_free_user_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          # Moving this up because it's likely to become a common access type
          async_limited_user_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          async_codespaces_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          async_seats_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          async_seat_assignments_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          async_billing_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            if access_type != :NOT_EVALUATED
              @subscription_type = access_type
              return promise.fulfill(access_type)
            end
          end

          # we need to handle EMUs who somehow got here.
          promise.fulfill(:ENTERPRISE_MANAGED) if @user_object.is_enterprise_managed?

          async_expired_coupon_check.then do |check|
            access_type = check.ok? ? check.value! : :NOT_EVALUATED
            return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
          end

          promise.fulfill(:NO_ACCESS)
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
            free_user = Copilot::FreeUser.find_by(user_id: @user_object.id)
            if free_user.present? && free_user.subscribed?
              handle_free_user_type(free_user)
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
            if !@user_object.feature_enabled?(:copilot_free_limited_user)
              log("Free limited flag not set")
              :NOT_EVALUATED
            else
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

              # load up all of the plans for this user's seats
              copilot_skus = seats.map(&:copilot_sku)

              log("User has at least one seat", { "gh.copilot.seats.count" => seats.count })
              # it's possible that the user has multiple seats, so we need to check all of them
              # we want to return the highest access type that we find
              # COPILOT_ENTERPRISE_TRIAL_SEAT then COPILOT_FOR_BUSINESS_TRIAL_SEAT then COPILOT_STANDALONE_SEAT
              # then COPILOT_ENTERPRISE_SEAT then COPILOT_FOR_BUSINESS_SEAT
              if copilot_skus.all?(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
                increment_access_type(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
              elsif copilot_skus.include?(:COPILOT_ENTERPRISE_TRIAL_SEAT)
                increment_access_type(:COPILOT_ENTERPRISE_TRIAL_SEAT)
              elsif copilot_skus.include?(:COPILOT_FOR_BUSINESS_TRIAL_SEAT)
                increment_access_type(:COPILOT_FOR_BUSINESS_TRIAL_SEAT)
              elsif copilot_skus.include?(:COPILOT_STANDALONE_SEAT)
                increment_access_type(:COPILOT_STANDALONE_SEAT)
              elsif copilot_skus.include?(:COPILOT_ENTERPRISE_SEAT)
                increment_access_type(:COPILOT_ENTERPRISE_SEAT)
              elsif copilot_skus.include?(:COPILOT_FOR_BUSINESS_SEAT)
                increment_access_type(:COPILOT_FOR_BUSINESS_SEAT)
              else
                log("User has no match for seat check")
                GitHub.dogstats.increment("copilot.authorizer.async_seats_check.no_match")
                :NOT_EVALUATED
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
            # let's see if this user has a Copilot::SeatAssignment record assigned to them or a group they belong to
            assignments = copilot_user.async_seat_assignments.sync

            if assignments.any?
              # this user has at least one Copilot::SeatAssignment record, so we need to prefill the copilot_sku association for the assignments
              GitHub::PrefillAssociations.prefill_batch_method(assignments, :copilot_sku)
              copilot_skus = assignments.map(&:copilot_sku)
              log("User has at least one seat assignment", { "gh.copilot.seat_assignments.count" => assignments.count })

              # it's possible that the user has multiple seat assignments, so we need to check all of them
              # we want to return the highest access type that we find
              # COPILOT_STANDALONE_SEAT_ASSIGNMENT then COPILOT_ENTERPRISE_SEAT_ASSIGNMENT then COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT
              if copilot_skus.all?(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
                increment_access_type(:COPILOT_FOR_BUSINESS_BILLING_LOCKED)
              elsif copilot_skus.include?(:COPILOT_STANDALONE_SEAT_ASSIGNMENT)
                increment_access_type(:COPILOT_STANDALONE_SEAT_ASSIGNMENT)
              elsif copilot_skus.include?(:COPILOT_ENTERPRISE_SEAT_ASSIGNMENT)
                increment_access_type(:COPILOT_ENTERPRISE_SEAT_ASSIGNMENT)
              elsif copilot_skus.include?(:COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT)
                increment_access_type(:COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT)
              elsif copilot_skus.include?(:COPILOT_STANDALONE_SEAT_ASSIGNMENT)
                increment_access_type(:COPILOT_STANDALONE_SEAT_ASSIGNMENT)
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
              subscribables = ::Billing::ProductUUID.where(product_type: "github.copilot", product_key: "v0")
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
                  interval = subscribable&.billing_cycle.to_sym
                  if on_free_trial
                    subscription << "TRIAL_30_"
                  end

                  if interval == :month
                    subscription << "MONTHLY"
                  elsif interval == :year
                    subscription << "YEARLY"
                  end
                  subscription << "_SUBSCRIBER"
                  subscription.string.to_sym
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

    sig { params(free_user: Copilot::FreeUser).returns(Symbol) }
    def handle_free_user_type(free_user)
      log("User is free user", free_user.to_otel)
      case free_user.type
      when ::Copilot::FreeUser::ENGAGED_OSS
        increment_access_type(:FREE_ENGAGED_OSS)
      when ::Copilot::FreeUser::EDUCATIONAL
        increment_access_type(:FREE_EDUCATIONAL)
      when ::Copilot::FreeUser::FACULTY
        increment_access_type(:FREE_FACULTY)
      when ::Copilot::FreeUser::GITHUB_STAR
        increment_access_type(:FREE_GITHUB_STAR)
      when ::Copilot::FreeUser::MS_MVP
        increment_access_type(:FREE_MS_MVP)
      when ::Copilot::FreeUser::Y_COMBINATOR
        increment_access_type(:FREE_Y_COMBINATOR)
      when ::Copilot::FreeUser::COMPLIMENTARY_ACCESS
        increment_access_type(:COMPLIMENTARY_ACCESS)
      when ::Copilot::FreeUser::HEY_GITHUB
        increment_access_type(:HEY_GITHUB)
      when ::Copilot::FreeUser::TECHNICAL_PREVIEW_EXTENSION
        increment_access_type(:TECHNICAL_PREVIEW_EXTENSION)
      when ::Copilot::FreeUser::WORKSHOP
        increment_access_type(:WORKSHOP)
      else
        increment_access_type(:OTHER_FREE_ACCESS)
      end
    end

    sig { params(access_type: Symbol).returns(Symbol) }
    def increment_access_type(access_type)
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
