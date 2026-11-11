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
      end
    end

    # Loads access type data for authorizer functionality that could not be extracted to CTS.
    # Calls the corresponding async methods for non-nil session fields and returns the result.
    # Only one of these checks should be true, so we return early after the first match.
    # We check both has_*? AND that the value is :ACCESS_TYPE_NOT_EVALUATED
    # because protobuf's to_h includes all fields with default values, which causes
    # has_*? to return true after deserialization even for unset fields.
    # Note: The protobuf accessor returns a Symbol, not the Integer constant.
    sig { returns(GitHub::Result) }
    def load_access_type
      not_evaluated = :ACCESS_TYPE_NOT_EVALUATED

      if @authorizer_session.has_billing_subscription_type? &&
         @authorizer_session.billing_subscription_type == not_evaluated
        return async_billing_check.sync
      end

      if @authorizer_session.has_codespace_user_access? &&
         @authorizer_session.codespace_user_access == not_evaluated &&
         !@user_object.feature_flag_enabled?(:copilot_disable_codespaces_demo, default: false)
        return async_codespaces_check.sync
      end

      GitHub::Result.new { :INVALID }
    end
  end
end
