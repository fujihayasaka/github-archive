# typed: strict
# frozen_string_literal: true

module Copilot
  class AuthorizerExtracted < Authorizer
    sig do
      params(
        copilot_user: Copilot::User,
        authorizer_session: MonolithTwirp::Copilot::Token::V1::AuthorizerSession,
        context: T.nilable(Context),
        env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
        include_snippy: T::Boolean,
      ).void
    end
    def initialize(copilot_user, authorizer_session, context = nil, env = {}, include_snippy: true)
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
      @authorizer_session = authorizer_session

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

    # Asynchronously determine the access type for this user
    sig { returns(Promise[Symbol]) }
    def async_access_type
      GitHub.logger.with_named_tags("code.function" => "async_access_type", "code.namespace" => self.class.name) do
        GitHub.tracer.in_span("copilot.authorizer.async_access_type") do |_span|
          log("Determining access type")
          promise = Promise.new

          return promise.fulfill(:NO_ACCESS) unless @user_object.feature_flag_enabled?(
            :copilot_token_service_m4_extraction, default: false
          )

          ###############################################################################################
          # 🚨 THE ORDER OF THESE CHECKS MATTERS, DO NOT CHANGE THEM UNLESS YOU KNOW WHAT YOU'RE DOING 🚨
          ###############################################################################################

          # We want to check the feature flags first because they should be relatively cheap
          # Also, if someone is feature flag blocked, we don't want to check anything else
          if @authorizer_session.has_properties_check?
            session_access_type = access_type_from_session(@authorizer_session.properties_check)
            return promise.fulfill(session_access_type) if session_access_type != :NOT_EVALUATED
          else
            async_properties_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
            end
          end

          # Then, we want to check whether the user is a free user, free meaning has a Copilot::LimitedUser record,
          # which allows to use Copilot, with a quota, with no subscription or payment method
          # For now only returns :FREE_LIMITED_COPILOT and :NOT_EVALUATED
          has_free_limited = T.let(false, T::Boolean)
          if @authorizer_session.has_has_free_limited?
            has_free_limited = @authorizer_session.has_free_limited
          else
            async_limited_user_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              has_free_limited = access_type == :FREE_LIMITED_COPILOT
            end
          end

          # Despite what this check is called, this is a check for whether the user has COMPLIMENTARY ACCESS,
          # AKA they have a Copilot::FreeUser record.
          if @authorizer_session.has_complimentary_access?
            session_access_type = access_type_from_session(@authorizer_session.complimentary_access)
            return promise.fulfill(session_access_type) if session_access_type != :NOT_EVALUATED
          else
            async_free_user_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
            end
          end

          # Then, we check whether the user subscribes monthly or yearly to one of the other copilot plans,
          # these are Pro, Pro+, and Max as of this comment; any INDIVIDUAL plan which has a SubscriptionItem
          if @authorizer_session.has_billing_subscription_type?
            session_access_type = access_type_from_session(@authorizer_session.billing_subscription_type)
            return promise.fulfill(session_access_type) unless BILLING_CHECK_BLOCKED_TYPES.include?(session_access_type)
          else
            async_billing_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              if access_type != :NOT_EVALUATED
                # we'll defer returning these blocked types until after we check for a seat or seat assignment
                # by fulfilling the promise with @subscription_type below if applicable
                @subscription_type = access_type
                return promise.fulfill(access_type) unless BILLING_CHECK_BLOCKED_TYPES.include?(access_type)
              end
            end
          end

          # Now we check whether the user has any Copilot::SeatAssignments, and if they all have access_revoked_at set,
          # we would defer the return :ACCESS_REVOKED, which is a BLOCKED_TYPE in the access loader.
          # 🚨 This check has to occur BEFORE the seats check
          all_seat_assignments_revoked = T.let(false, T::Boolean)
          if @authorizer_session.has_seat_assignment?
            session_access_type = access_type_from_session(@authorizer_session.seat_assignment)
            all_seat_assignments_revoked = session_access_type == :ACCESS_REVOKED
          else

            async_seat_assignments_revoked_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              all_seat_assignments_revoked = access_type == :ACCESS_REVOKED
            end
          end

          # Now we check for any Copilot::Seats and if any exist, we return the appropriate SKU as the access type
          if @authorizer_session.has_seat_sku?
            session_access_type = access_type_from_session(@authorizer_session.seat_sku)
            return promise.fulfill(session_access_type) if session_access_type != :NOT_EVALUATED
          else
            async_seats_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
            end unless all_seat_assignments_revoked
          end

          # We will only fall through to here and return an actual SKU if the user only has seat assignments
          # that are not associated with seats which are not already pending cancellation, this is EXTREMELY RARE,
          # and should only happen within the cooldown period.
          if @authorizer_session.has_seat_assignment?
            session_access_type = access_type_from_session(@authorizer_session.seat_assignment)
            return promise.fulfill(session_access_type) if session_access_type != :NOT_EVALUATED
          else
            async_seat_assignments_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
            end unless all_seat_assignments_revoked
          end

          # this is for a codespace demo user
          if @authorizer_session.has_codespace_user_access?
            session_access_type = access_type_from_session(@authorizer_session.codespace_user_access)
            return promise.fulfill(session_access_type) if session_access_type != :NOT_EVALUATED
          else
            async_codespaces_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
            end
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
          if @authorizer_session.has_coupon_check? &&
            session_access_type = access_type_from_session(@authorizer_session.coupon_check)
            return promise.fulfill(session_access_type) if session_access_type != :NOT_EVALUATED
          else
            async_expired_coupon_check.then do |check|
              access_type = check.ok? ? check.value! : :NOT_EVALUATED
              return promise.fulfill(access_type) if access_type != :NOT_EVALUATED
            end
          end

          # catchall
          promise.fulfill(:NO_ACCESS)
        end
      end
    end

    # This is used because the CTS AccessType is of the form :ACCESS_TYPE_<TYPE> - we want to have backwards
    # compatibility with the monolith's existing symbols.
    sig { params(type: T.any(Symbol, Integer)).returns(T.nilable(Symbol)) }
    private def access_type_from_session(type)
      return nil if type == :ACCESS_TYPE_INVALID

      # if the type is an integer, we need to look it up, shouldn't happen by default ruby proto behavior
      if type.is_a?(Integer)
        type = MonolithTwirp::Copilot::Token::V1::AccessType.lookup(type)
      end

      type.to_s.delete_prefix("ACCESS_TYPE_").to_sym
    end
  end
end
