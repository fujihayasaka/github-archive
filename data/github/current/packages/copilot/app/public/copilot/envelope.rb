# typed: strict
# frozen_string_literal: true

module Copilot
  class Envelope
    extend T::Helpers

    include FeatureFlagHelper
    include GitHub::Memoizer

    NotificationEnvelope = T.type_alias do
      {
        message: String,
        notification_id: String,
        title: String,
        url: String,
      }
    end

    TokenEnvelope = T.type_alias do
      {
        agent_mode_auto_approval: T::Boolean,
        annotations_enabled: T::Boolean,
        azure_only: T::Boolean,
        blackbird_clientside_indexing: T::Boolean,
        blackbird_external_indexing: T::Boolean,
        chat_enabled: T::Boolean,
        chat_jetbrains_enabled: T::Boolean,
        code_quote_enabled: T::Boolean,
        code_review_enabled: T::Boolean,
        codesearch: T::Boolean,
        copilotignore_enabled: T::Boolean,
        endpoints: T.nilable(SKUIsolation::Endpoints),
        enterprise_list: T.nilable(T::Array[String]),
        expires_at: Integer,
        iat: Integer,
        individual: T::Boolean,
        limited_user_quotas: T.nilable(T::Hash[String, Integer]),
        limited_user_reset_date: T.nilable(Integer),
        organization_list: T.nilable(T::Array[String]),
        public_suggestions: String,
        refresh_in: Integer,
        sku: String,
        telemetry: String,
        token: String,
        tracking_id: String,
        xcode_chat: T::Boolean,
        xcode: T::Boolean,
      }
    end

    ErrorEnvelope = T.type_alias do
      {
        error_details: NotificationEnvelope,
        message: String,
        reason: T.nilable(String),
        can_signup_for_limited: T::Boolean,
      }
    end

    AccessEnvelope = T.type_alias { T.any({}, TokenEnvelope, ErrorEnvelope) }

    include Copilot::Metrics

    HMAC_ALGORITHM           = T.let("sha256".freeze, String)
    MAGIC_API_VERSION        = T.let("2024-12-15".freeze, String)

    ##### URLS for editor notifications #####
    # These have the ?editor={EDITOR} in them. this will be subbed out by the editor
    BILLING_SETTINGS_PAGE    = T.let("https://github.com/settings/billing/summary?editor={EDITOR}".freeze, String)
    PLANS_PAGE               = T.let("https://github.com/features/copilot/plans?editor={EDITOR}".freeze, String)
    SETTINGS_PAGE            = T.let("https://github.com/settings/copilot?editor={EDITOR}".freeze, String)
    SIGNUP_PAGE              = T.let("https://github.com/github-copilot/signup?editor={EDITOR}".freeze, String)
    SUPPORT_PAGE             = T.let("#{GitHub.support_url}?editor={EDITOR}".freeze, String)
    WAITLIST_SIGNUP_PAGE     = T.let("https://github.com/features/copilot/signup?editor={EDITOR}".freeze, String)

    sig { returns(AccessEnvelope) }
    attr_reader :envelope

    sig { params(authorizer: Copilot::Authorizer, headers: T::Hash[Symbol, String], cap_filter: T.nilable(ConditionalAccess::Filter)).void }
    def initialize(authorizer, headers, cap_filter = nil)
      @authorizer       = authorizer
      @copilot_user     = T.let(authorizer.copilot_user, Copilot::User)
      @user_object      = T.let(@copilot_user.user_object, ::User)
      @headers          = headers
      @api_version      = T.let(headers.fetch(:github_api_version, ""), String)
      @token_issued_at  = T.let(Time.now.to_i, Integer)
      @cap_filter       = cap_filter

      @envelope         = T.let({}, AccessEnvelope)

      @expiration = T.let(Copilot::TokenExpiration.new(@copilot_user, quota_remaining_percentage: quota_remaining_percentage), Copilot::TokenExpiration)
      @refresh    = T.let(Copilot::TokenRefresh.new(@copilot_user, quota_remaining_percentage: quota_remaining_percentage), Copilot::TokenRefresh)

      load_envelope
    end

    sig { returns(Float) }
    memoize def quota_remaining_percentage
      return 100.0 unless @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_free_token_refresh) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      return 100.0 unless @copilot_user.limited_user.present?

      limited_user = T.must(@copilot_user.limited_user)
      limited_user.feature_quota_percentage_remaining(feature: "completions")
    end

    # this method is only called in tests and from the token envelope (success path below)
    # so it's okay to not check for access
    sig { returns(String) }
    memoize def generate_v2_token
      editor_preview_features_enabled = @copilot_user.editor_preview_features_enabled?
      agent_mode_disabled = Copilot::Policies::AgentMode.effective_value(@copilot_user) == "disabled"
      if @user_object.feature_flag_enabled?(:copilot_token_service_agent_mode_token_debug_production, default: false)
        log_agent_mode_debug(agent_mode_disabled)
      end
      agent_mode_auto_approval = @copilot_user.agent_mode_auto_approve_enabled?
      mcp_enabled = @copilot_user.mcp_enabled?
      blackbird_external_indexing_enabled = blackbird_external_indexing_enabled?
      client_byok_enabled = Copilot::Policies::ClientByok.available_for?(@copilot_user) &&
        Copilot::Policies::ClientByok.effective_value(@copilot_user) == "enabled"
      message = "tid=#{analytics_tracking_id}"
      message += ";ol=#{org_tracking_ids.join(',')}" unless org_tracking_ids.empty?
      message += ";exp=#{token_expiration}"
      message += ";iat=#{@token_issued_at}"
      message += ";sku=#{@authorizer.access_type_sku}"
      message += ";proxy-ep=#{sku_isolation.proxy.host}" if sku_isolation.enforce_proxy?
      message += ";st=#{stamp}"
      message += ";ssc=1" if @authorizer.has_ssc?
      message += ";chat=1" if @copilot_user.chat_enabled?
      message += ";sn=1" if snippy_enabled?
      message += ";cit=1" if code_citations_enabled?
      message += ";snp=1" if snippy_prompt_overlap?
      message += ";malfil=1" if malware_filtering?
      message += ";editor_preview_features=0" if !editor_preview_features_enabled
      message += ";editor_preview_features=1" if editor_preview_features_enabled
      message += ";agent_mode=0" if agent_mode_disabled
      message += ";agent_mode=1" if !agent_mode_disabled
      message += ";agent_mode_auto_approval=0" if !agent_mode_auto_approval
      message += ";agent_mode_auto_approval=1" if agent_mode_auto_approval
      message += ";mcp=0" if !mcp_enabled
      message += ";mcp=1" if mcp_enabled
      message += ";blackbird_external_indexing=0" if !blackbird_external_indexing_enabled
      message += ";blackbird_external_indexing=1" if blackbird_external_indexing_enabled
      message += ";client_byok=0" if !client_byok_enabled
      message += ";client_byok=1" if client_byok_enabled
      message += ";ccr=1" if @copilot_user.copilot_code_review_enabled?
      message += ";rt=1" if telemetry_enabled?
      message += ";ft=#{fine_tuning_identifier}" if fine_tuning_identifier
      message += ";rag=#{rag_identifier}" if rag_identifier
      message += ";ip=#{@headers[:real_ip]&.gsub(":", "-")}" if include_network_information? && @headers[:real_ip].present?
      message += ";asn=#{@headers[:asn]}" if include_network_information? && @headers[:asn].present?
      message += ";fcv1=1" if force_copilot_codex_v1?
      message += ";ao=1" if azure_only?
      message += ";fo=1" if fedramp_only?
      message += ";sl=0" if monitor_feature_enabled? && !monitor_enabled?
      message += ";sl=1" if monitor_feature_enabled? && monitor_enabled?

      # we check for feature flag and membership in the method
      message = add_ci_free_details_to_token(message)
      mac = OpenSSL::HMAC.hexdigest(HMAC_ALGORITHM, GitHub.copilot_cdn_hmac_key.to_s, message)
      "#{message}:#{mac}"
    end

    sig { returns(T::Boolean) }
    memoize def monitor_enabled?
      CopilotContentSafety::MonitoringState.monitored?(@user_object)
    end

    sig { returns(T::Boolean) }
    def monitor_feature_enabled?
      @copilot_user.feature_flag_enabled?(:copilot_token_sl_in_token, default: false)
    end

    sig { returns(T::Boolean) }
    def azure_only?
      Copilot::Policies::RestrictToAzure.effective_value(@copilot_user) == "enabled"
    end

    sig { returns(T::Boolean) }
    def fedramp_only?
      Copilot::Policies::RestrictToFedramp.effective_value(@copilot_user) == "enabled"
    end

    sig { returns(T::Boolean) }
    def data_residency_only?
      Copilot::Policies::RestrictToDataResidency.effective_value(@copilot_user) == "enabled"
    end

    sig { returns(T::Boolean) }
    def malware_filtering?
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_malware_filtering) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def snippy_enabled?
      return false if snippy_blocking_disabled?
      return false if @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_force_code_references) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      # Partner users always have snippy enabled, regardless of the Duplicate
      # Detection Filter policy.
      return true if @copilot_user.is_partner_user?
      return false unless @copilot_user.block_public_code_suggestions?
      return false if duplicate_detection_filter_policy_disabled?
      true
    end

    sig { returns(T::Boolean) }
    def code_citations_enabled?
      return false if snippy_enabled?
      return false if snippy_citations_disabled?
      return false unless @copilot_user.user_object.feature_flag_enabled?(:copilot_code_citations, default: false)
      return false if duplicate_detection_filter_policy_disabled?
      true
    end

    sig { returns(T::Boolean) }
    def duplicate_detection_filter_policy_disabled?
      return false unless duplicate_detection_filter_feature_flag_enabled?
      return false unless Copilot::Policies::DuplicateDetectionFilter.available_for?(@copilot_user)
      Copilot::Policies::DuplicateDetectionFilter.disabled?(@copilot_user)
    end

    sig { returns(T::Boolean) }
    def duplicate_detection_filter_feature_flag_enabled?
      @copilot_user.user_object.feature_flag_enabled?(:copilot_token_service_snippy_opt_out_policy, default: false)
    end

    sig { returns(T::Boolean) }
    def snippy_prompt_overlap?
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_snippy_prompt_overlap) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def snippy_blocking_disabled?
      snippy_blocking_globally_disabled? && !snippy_blocking_reenabled?
    end

    sig { returns(T::Boolean) }
    def snippy_blocking_globally_disabled?
      # snippy may be disabled for experiments relating to Project Heat
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_snippy_blocking_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def snippy_blocking_reenabled?
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_snippy_blocking_reenabled) || # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @copilot_user.copilot_organizations.any? { |org| org.feature_flag_enabled_or_raise?(:copilot_snippy_blocking_reenabled) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def snippy_citations_disabled?
      snippy_citations_globally_disabled? && !snippy_citations_reenabled?
    end

    sig { returns(T::Boolean) }
    def snippy_citations_globally_disabled?
      # snippy may be disabled for experiments relating to Project Heat
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_snippy_annotations_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def snippy_citations_reenabled?
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_snippy_annotations_reenabled) || # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @copilot_user.copilot_organizations.any? { |org| org.feature_flag_enabled_or_raise?(:copilot_snippy_annotations_reenabled) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(String) }
    def stamp
      GitHub.copilot_stamp.presence || "dotcom"
    end

    sig { returns(T::Boolean) }
    def telemetry_enabled?
      return false if GitHub.multi_tenant_enterprise?

      @copilot_user.telemetry_enabled?
    end

    sig { returns(T::Boolean) }
    def blackbird_external_indexing_enabled?
      @copilot_user.blackbird_external_indexing_enabled?
    end

    sig { returns(T.nilable(String)) }
    memoize def fine_tuning_identifier
      if multiple_fine_tuning_identifiers?
        orgs = @copilot_user.fine_tuning_organizations
        return unless orgs.any?
        orgs.map { |org| "org_#{org.analytics_tracking_id}" }.join(",")
      else
        org = @copilot_user.fine_tuning_organization
        return unless org
        "org_#{org.analytics_tracking_id}"
      end
    end

    sig { returns(T.nilable(String)) }
    memoize def rag_identifier
      org = @copilot_user.rag_organization
      "org_#{org.analytics_tracking_id}" if org
    end

    sig { params(headers: T::Hash[Symbol, String]).void }
    def instrument_token_generation(headers = {})
      Copilot::Instrumenter.instrument_token_generated(
        @copilot_user,
        token_expiration,
        @authorizer.access_type,
        headers,
        @authorizer.organization_list,
      )
    end

    sig { params(failure_reason: String, headers: T::Hash[Symbol, String]).void }
    def instrument_token_failure(failure_reason, headers)
      if @user_object.is_enterprise_managed?
        failure_reason = "enterprise_managed_user"
      end
      if failure_reason == "no_access"
        failure_reason = (@api_version == MAGIC_API_VERSION) ? "not_signed_up" : "no_copilot_access"
      end
      Copilot::Instrumenter.instrument_token_failed(@copilot_user, failure_reason, headers)
    end

    sig { returns(SKUIsolation) }
    memoize def sku_isolation
      if @copilot_user.feature_flag_enabled?(:copilot_sku_isolation_use_public_user_perf, default: false)
        SKUIsolation.for_user(@user_object)
      else
        SKUIsolation.new(@copilot_user, GitHub::CurrentTenant.get)
      end
    end

    private

    sig { void }
    def load_envelope
      if @authorizer.access_allowed?
        load_token_envelope
      else
        load_error_envelope
      end
    end

    sig { void }
    def load_token_envelope
      @envelope = {
        agent_mode_auto_approval: @copilot_user.agent_mode_auto_approve_enabled?,
        annotations_enabled: @copilot_user.annotations_enabled?,
        azure_only: azure_only?,
        blackbird_clientside_indexing: @copilot_user.feature_flag_enabled_or_raise?(:blackbird_clientside_indexing), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        blackbird_external_indexing: blackbird_external_indexing_enabled?,
        chat_enabled: @copilot_user.chat_enabled?,
        chat_jetbrains_enabled: true,
        code_quote_enabled: @copilot_user.codequote_enabled?,
        code_review_enabled: @copilot_user.copilot_code_review_enabled?,
        codesearch: true,
        copilotignore_enabled: @copilot_user.copilot_content_exclusion_enabled?,
        endpoints: sku_isolation.endpoints,
        expires_at: token_expiration,
        iat: @token_issued_at,
        individual: @copilot_user.has_cfi_access?, # this means the user is an individual user so VS can leverage that
        public_suggestions: @copilot_user.snippy_setting,
        refresh_in: token_refresh_in,
        sku: @authorizer.access_type_sku,
        telemetry: @copilot_user.telemetry_setting,
        token: generate_v2_token,
        tracking_id: analytics_tracking_id,
        xcode_chat: xcode_chat_enabled?,
        xcode: xcode_enabled?,
      }

      @envelope[:organization_list] = org_tracking_ids unless org_tracking_ids.empty?
      # enterprise_list is an array of Copilot::Business objects, so we want to grab their IDs
      @envelope[:enterprise_list] = business_list.collect(&:id) unless business_list.empty?

      @envelope[:limited_user_quotas] = feature_quotas
      @envelope[:limited_user_reset_date] = limited_user_reset_date

      if @copilot_user.user_object.feature_flag_enabled?(:copilot_token_service_log_copilot_configs, default: false)
        config_ids = []
        config_ids << @copilot_user.configuration.id if @copilot_user.has_configuration?
        @copilot_user.copilot_organizations.each do |org|
          config_ids << org.configuration.id if org.has_configuration?
        end
        @copilot_user.copilot_businesses.each do |biz|
          config_ids << biz.configuration.id if biz.has_configuration?
        end

        GitHub.logger.info("Copilot config IDs for user", {
          "gh.copilot.config_ids" => config_ids.join(","),
          "gh.user.id" => @copilot_user.id,
        })
      end
    end

    sig { void }
    def load_error_envelope
      GitHub.logger.with_named_tags({
        "code.function": "load_error_envelope",
        "code.namespace": "Copilot::Envelope",
        "gh.user.id": @copilot_user.id,
        "gh.copilot.editor_version": @headers[:editor_version],
        "gh.copilot.editor_plugin_version": @headers[:editor_plugin_version],
        "gh.copilot.envelope.failure_reason": @authorizer.reason,
        "gh.copilot.envelope.api_version": @api_version,
      }) do
        @envelope = {
          message: "Resource not accessible by integration",
          can_signup_for_limited: @copilot_user.can_signup_for_limited?,
        }

        # reason is a lower case string
        case @authorizer.reason
        when "subscription_ended"
          subscription_ended_error
        when "feature_flag_blocked"
          feature_flag_blocked_error
        when "spammy_user"
          spammy_user_error
        when "billing_locked"
          billing_locked_error
        when "enterprise_managed"
          emu_error
        when "trade_restricted", "trade_restricted_country"
          trade_restricted_error
        when "codespaces_demo_inactive"
          codespaces_demo_error
        when "no_access"
          default_error
        when "server_error"
          server_error
        when "snippy_not_configured"
          snippy_not_configured_error
        when "expired_coupon", "revoked_coupon"
          bad_coupon_error
        when "go_http_client", "programmatic_token_generation"
          programmatic_token_error
        when "access_revoked"
          access_revoked_error
        else
          default_error
        end
      end
    end

    sig { params(message: String).returns(String) }
    def add_ci_free_details_to_token(message)
      return message unless @authorizer.access_type == :FREE_LIMITED_COPILOT
      return message unless @copilot_user.limited_user.present?

      limited_user = T.must(@copilot_user.limited_user)
      completions_quota = limited_user.feature_quota_remaining(feature: "completions")

      message += ";cq=#{completions_quota}" # matching with https://github.com/github/gopilot/blob/main/hmac/auth.go#L407

      return message unless limited_user.reset_date.present?

      reset_date = DateTime.new(
        limited_user.reset_date.year,
        limited_user.reset_date.month,
        limited_user.reset_date.day,
      ).to_i

      message += ";rd=#{reset_date}"
      message
    end

    # since editors have untrusty clocks (they aren't synced to our servers, sadly) we need
    # to include this value so that the editor can calculate client side when they should refresh
    # the token. we are making this a little less than the token_expiration/server side time
    # so that we can have a little bit of leeway
    sig { returns(Integer) }
    memoize def token_refresh_in
      # Ensure refresh_in never exceeds the time remaining until token expiration.
      # VS Code relies on this value never exceeding the expiration date.
      # token_expiration is a timestamp, so we calculate seconds remaining.
      seconds_until_expiration = token_expiration - Time.now.to_i
      if @refresh.token_refresh_in >= seconds_until_expiration
        # Due to the way the VS client sets up their reset scheduler, we need to ensure there is no discrepency
        # between the expiration and refresh values
        return [seconds_until_expiration - 60, 0].max
      end

      @refresh.token_refresh_in
    end

    # this is the value included in the token that denotes the SERVER SIDE (NTP synced hopefully)
    # time in a unix timestamp format that the proxy should reject this token
    sig { returns(Integer) }
    memoize def token_expiration
      @expiration.token_expiration.seconds.from_now.to_i
    end

    sig { returns(T.nilable(T::Hash[String, Integer])) }
    def feature_quotas
      GitHub.logger.info("Loading limited user")
      limited_user = Copilot::LimitedUser.for_subscribed_user(@copilot_user.user_object)

      if limited_user.present?
        GitHub.logger.info("Limited user found", { "gh.copilot.limited_user.id" => limited_user.id })
        return limited_user.quotas_remaining
      end

      GitHub.logger.info("No limited user found")
      nil
    end

    sig { returns(T.nilable(Integer)) }
    def limited_user_reset_date
      limited_user = Copilot::LimitedUser.for_subscribed_user(@copilot_user.user_object)
      return nil unless limited_user.present?

      # this user is subscribed so they WILL have a reset date.
      # that being said, this is the big city and we don't trust anything
      return nil unless limited_user.reset_date.present?

      # surprise surprise - we didn't blow it
      DateTime.new(
        limited_user.reset_date.year,
        limited_user.reset_date.month,
        limited_user.reset_date.day,
      ).to_i
    end

    # Returns the analytics tracking id for the user
    sig { returns(String) }
    def analytics_tracking_id
      @copilot_user.user_object.analytics_tracking_id.to_s
    end

    # Returns a list of analytic tracking ids for the orgs the user is a member of
    sig { returns(T::Array[String]) }
    memoize def org_tracking_ids
      @authorizer.organization_list
    end

    # Returns a list of Businesses for the orgs the user is a member of
    sig { returns(T::Array[Copilot::Business]) }
    memoize def business_list
      @copilot_user.copilot_businesses.compact.uniq
    end

    sig { params(msg: String).returns(String) }
    def add_user_to_msg(msg)
      "#{msg} You are currently logged in as #{@copilot_user.user_object.display_login}."
    end

    sig { void }
    def server_error
      @envelope[:error_details] = {
        url: SUPPORT_PAGE,
        message: "Contact Support.",
        title: "Contact Support",
        notification_id: "server_error"
      }
    end

    sig { void }
    def codespaces_demo_error
      @envelope[:error_details] = {
        url: COPILOT_PRICING_PAGE,
        message: add_user_to_msg("We appreciate your interest in the Copilot+Codespaces Demo Experience! Please register for a trial to continue to use Copilot!"),
        title: "Sign up for GitHub Copilot",
        notification_id: "codespaces_demo_inactive",
      }

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, "codespaces_demo_inactive", @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:codespaces_demo_inactive", "event:shown"],
      )
      GitHub.logger.info("Codespaces demo session ended")
    end

    sig { void }
    def default_error
      notification_id = (@api_version == MAGIC_API_VERSION) ? "not_signed_up" : "no_copilot_access"

      @envelope[:error_details] = {
        url: SIGNUP_PAGE,
        message: add_user_to_msg("No access to GitHub Copilot found."),
        title: "Sign up for GitHub Copilot",
        notification_id: notification_id,
      }
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:default_error", "event:shown", "api_version_matches:#{@api_version == MAGIC_API_VERSION}"],
      )
      GitHub.logger.info("No access to GitHub Copilot found")
    end

    sig { void }
    def bad_coupon_error
      @envelope[:error_details] = {
        url: SIGNUP_PAGE,
        message: add_user_to_msg("No access to GitHub Copilot found."),
        title: "Sign up for GitHub Copilot",
        notification_id: @authorizer.reason,
      }
      if @authorizer.reason == "revoked_coupon"
        # we are specifically not allowing these users to sign up for the limited experience
        @envelope[:can_signup_for_limited] = false
      end

      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:#{@authorizer.reason}", "event:shown"],
      )
      GitHub.logger.info("Expired or revoked coupon")
    end

    sig { void }
    def snippy_not_configured_error
      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, "snippy_not_configured", @headers)

      @envelope[:error_details] = {
        url: SETTINGS_PAGE,
        message: add_user_to_msg("Your Copilot experience is not fully configured, complete your setup."),
        title: "Copilot Settings",
        notification_id: "snippy_not_configured",
      }

      # we are specifically not allowing these users to sign up for the limited experience
      # because they are already signed up and just need to configure things
      @envelope[:can_signup_for_limited] = false

      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:snippy_not_configured_error", "event:shown"],
      )
      GitHub.logger.info("No access to GitHub Copilot found")
    end

    sig { void }
    def emu_error
      @envelope[:error_details] = {
        message: add_user_to_msg("Please contact your enterprise admin to enable your managed account for Copilot Business."),
        url: "https://github.com",
        title: "OK", # this is what the button says in the editor
        notification_id: "enterprise_managed_user_account",
      }

      # we are specifically not allowing these users to sign up for the limited experience
      # because they are EMU users
      @envelope[:can_signup_for_limited] = false

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, "enterprise_managed_user_account", @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:enterprise_managed_user_account", "event:shown"],
      )
      GitHub.logger.info("EMU user account")
    end

    sig { void }
    def feature_flag_blocked_error
      @envelope[:error_details] = {
        url: SUPPORT_PAGE,
        message: add_user_to_msg("Contact Support."),
        title: "Contact Support",
        notification_id: "feature_flag_blocked",
      }

      # we are specifically not allowing these users to sign up for the limited experience
      # because they are copilot abusers
      @envelope[:can_signup_for_limited] = false

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, "feature_flag_blocked", @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:feature_flag_blocked", "event:shown"],
      )
      GitHub.logger.info("Feature flag blocked")
    end

    sig { void }
    def trade_restricted_error
      @envelope[:error_details] = {
        url: COPILOT_TRADE_CONTROLS_DOCUMENTATION,
        message: add_user_to_msg("At this time, Copilot is not available in your location."),
        title: "Copilot Unavailable",
        notification_id: @authorizer.reason,
      }

      # we are specifically not allowing these users to sign up for the limited experience
      # because they are trade restricted
      @envelope[:can_signup_for_limited] = false

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, @authorizer.reason, @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:#{@authorizer.reason}", "event:shown"],
      )
      GitHub.logger.info("Trade restricted")
    end

    sig { void }
    def subscription_ended_error
      @envelope[:error_details] = {
        message: add_user_to_msg("Thank you for using GitHub Copilot. Your subscription has ended."),
        url: SETTINGS_PAGE,
        title: "Copilot Settings",
        notification_id: "subscription_ended",
      }
      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, "subscription_ended", @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:subscription_ended", "event:shown"],
      )
      GitHub.logger.info("Subscription ended")
    end

    sig { void }
    def billing_locked_error
      @envelope[:error_details] = {
        url: BILLING_SETTINGS_PAGE,
        message: add_user_to_msg("Your account's billing is currently locked because recent account charges have failed. Please check the 'Billing & plans' section in your settings."),
        title: "Billing Settings",
        notification_id: "billing_locked",
      }

      # we are specifically not allowing these users to sign up for the limited experience
      # because their billing is locked which usually indicates a problem
      @envelope[:can_signup_for_limited] = false

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, "billing_locked", @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:billing_locked", "event:shown"],
      )
      GitHub.logger.info("Billing locked user")
    end

    sig { void }
    def spammy_user_error
      @envelope[:error_details] = {
        url: SUPPORT_PAGE,
        message: add_user_to_msg("Contact Support."),
        title: "Contact Support",
        notification_id: "spammy_user",
      }

      # we are specifically not allowing these users to sign up for the limited experience
      # because they are marked as spammy
      @envelope[:can_signup_for_limited] = false

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, "spammy_user", @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:spammy_user", "event:shown"],
      )
      GitHub.logger.info("Spammy user")
    end

    sig { void }
    def programmatic_token_error
      @envelope[:error_details] = {
        url: SUPPORT_PAGE,
        message: add_user_to_msg("Please only use approved clients for Copilot."),
        title: "Copilot Unavailable",
        notification_id: @authorizer.reason,
      }

      # setting this to nil so it doesn't show up
      @envelope[:can_signup_for_limited] = nil

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, @authorizer.reason, @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:#{@authorizer.reason}", "event:shown"],
      )
      GitHub.logger.info("Trade restricted")
    end

    sig { void }
    def access_revoked_error
      @envelope[:error_details] = {
        url: SETTINGS_PAGE,
        message: add_user_to_msg("Your Copilot access has been revoked by the providing organization or enterprise."),
        title: "Copilot Settings",
        notification_id: "access_revoked",
      }

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, "access_revoked", @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:access_revoked", "event:shown"],
      )
      GitHub.logger.info("Access revoked user")
    end

    sig { returns(T::Boolean) }
    def include_network_information?
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_token_include_network_information) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def multiple_fine_tuning_identifiers?
      flag = :copilot_custom_models_multi_ft
      @copilot_user.user_object.feature_flag_enabled_or_raise?(flag) || # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @copilot_user.copilot_businesses.all? { |biz| biz.feature_flag_enabled_or_raise?(flag) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def xcode_enabled?
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_xcode) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def xcode_chat_enabled?
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_xcode_chat) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    # force code completions to use the codex v1 model - needed to support special customers that need to get compliance approval for CodexV2
    # see https://github.com/github/copilot/issues/16588
    sig { returns(T::Boolean) }
    def force_copilot_codex_v1?
      @copilot_user.user_object.feature_flag_enabled_or_raise?(:copilot_force_completions_codex_v1) || # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @copilot_user.copilot_organizations.any? { |org| org.feature_flag_enabled_or_raise?(:copilot_force_completions_codex_v1) } || # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @copilot_user.copilot_businesses.any? { |biz| biz.feature_flag_enabled_or_raise?(:copilot_force_completions_codex_v1) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { params(agent_mode_disabled: T::Boolean).void }
    def log_agent_mode_debug(agent_mode_disabled)
      effective = Copilot::Policies::AgentMode.effective_value(@copilot_user)

      # Collect all_policies data
      all_policies = @copilot_user.all_policies

      # Check flag states
      flag_disabled = @copilot_user.feature_flag_enabled?(:agent_mode_policy_disabled, default: false)
      flag_enabled = @copilot_user.feature_flag_enabled?(:agent_mode_policy_enabled, default: false)
      is_cfi = @copilot_user.has_cfi_access?

      # Check what the policy inheritance returns (without the || "enabled" default)
      biz_configs = all_policies.select { |pd| pd[:type] == :business }.map { |pd| "#{pd[:id]}:#{pd[:config]&.[](:agent_mode)}" }.join(",")
      org_configs = all_policies.select { |pd| pd[:type] == :organization }.map { |pd| "#{pd[:id]}:#{pd[:config]&.[](:agent_mode)}" }.join(",")

      GitHub.logger.info(
        "copilot_agent_mode_token_debug",
        "gh.user.id" => @user_object.id,
        "gh.user.analytics_tracking_id" => @user_object.analytics_tracking_id,
        "gh.copilot.agent_mode.effective_value" => effective,
        "gh.copilot.agent_mode.agent_mode_disabled" => agent_mode_disabled,
        "gh.copilot.agent_mode.flag_disabled" => flag_disabled,
        "gh.copilot.agent_mode.flag_enabled" => flag_enabled,
        "gh.copilot.agent_mode.is_cfi" => is_cfi,
        "gh.copilot.agent_mode.access_type" => @copilot_user.access_type.to_s,
        "gh.copilot.agent_mode.biz_configs" => biz_configs,
        "gh.copilot.agent_mode.org_configs" => org_configs,
        "gh.copilot.agent_mode.policy_count" => all_policies.size,
      )
    rescue => e
      GitHub.logger.error("copilot_agent_mode_token_debug_error", "error" => e.message)
    end
  end
end
