# typed: strict
# frozen_string_literal: true

module Copilot
  class EnvelopeExtracted < Envelope

    PLANS_PAGE            = Copilot::Envelope::PLANS_PAGE
    SIGNUP_PAGE           = Copilot::Envelope::SIGNUP_PAGE
    SETTINGS_PAGE         = Copilot::Envelope::SETTINGS_PAGE
    SUPPORT_PAGE          = Copilot::Envelope::SUPPORT_PAGE
    BILLING_SETTINGS_PAGE = Copilot::Envelope::BILLING_SETTINGS_PAGE
    HMAC_ALGORITHM        = Copilot::Envelope::HMAC_ALGORITHM

    sig { returns(AccessEnvelope) }
    attr_reader :envelope

    sig do
      params(
        authorizer: T.nilable(Copilot::Authorizer), # TODO: this should go away eventually for good
        headers: T::Hash[Symbol, String],
        cap_filter: T.nilable(ConditionalAccess::Filter),
        feature_flags: T.nilable(T::Hash[Symbol, T::Boolean]),
        envelope_builder: T.nilable(MonolithTwirp::Copilot::Token::V1::EnvelopeBuilder),
        copilot_user: T.nilable(Copilot::User)
      ).void
    end
    def initialize(authorizer, headers, cap_filter = nil, feature_flags = nil, envelope_builder = nil, copilot_user = nil)
      user = authorizer&.copilot_user || copilot_user
      raise ArgumentError, "copilot_user is required" unless user

      @authorizer       = authorizer
      @copilot_user     = T.let(user, Copilot::User)
      @user_object      = T.let(@copilot_user.user_object, ::User)
      @headers          = headers
      @api_version      = T.let(headers.fetch(:github_api_version, ""), String)
      @cap_filter       = cap_filter

      @feature_flags    = feature_flags

      @envelope_builder = envelope_builder

      @envelope         = T.let({}, AccessEnvelope)

      @expiration = T.let(Copilot::TokenExpiration.new(@copilot_user, quota_remaining_percentage: quota_remaining_percentage), Copilot::TokenExpiration)
      @refresh    = T.let(Copilot::TokenRefresh.new(@copilot_user, quota_remaining_percentage: quota_remaining_percentage), Copilot::TokenRefresh)

      load_envelope
    end

    sig { returns(Float) }
    memoize def quota_remaining_percentage
      # If CTS map contains the flag (even false), trust it; only fallback if missing
      return 100.0 unless feature_flag_from_cts(:copilot_free_token_refresh)
      return 100.0 unless @copilot_user.limited_user.present?

      limited_user = T.must(@copilot_user.limited_user)
      limited_user.feature_quota_percentage_remaining(feature: "completions")
    end

    # this method is only called in tests and from the token envelope (success path below)
    # so it's okay to not check for access
    sig { returns(String) }
    memoize def generate_v2_token
      builder = @envelope_builder

      editor_preview_features_enabled = builder&.has_editor_preview_features_enabled? ? builder.editor_preview_features_enabled : @copilot_user.editor_preview_features_enabled?
      agent_mode_disabled = builder&.has_agent_mode_enabled? ? !builder.agent_mode_enabled : @copilot_user.agent_mode_disabled?
      agent_mode_auto_approval = @copilot_user.agent_mode_auto_approve_enabled?
      mcp_enabled = builder&.has_mcp_enabled? ? builder.mcp_enabled : @copilot_user.mcp_enabled?

      tracking_id = builder&.has_tracking_id? ? builder.tracking_id : analytics_tracking_id
      message = "tid=#{tracking_id}"

      org_list = (builder && builder.organization_list.present?) ? builder.organization_list : org_tracking_ids
      message += ";ol=#{org_list.join(',')}" unless org_list.empty?

      exp = builder&.has_expires_at? ? builder.expires_at : token_expiration
      message += ";exp=#{exp}"

      message += ";sku=#{access_type_sku}"

      if builder&.has_proxy_endpoint?
        message += ";proxy-ep=#{builder.proxy_endpoint}"
      elsif sku_isolation.enforce_proxy?
        message += ";proxy-ep=#{sku_isolation.proxy.host}"
      end

      st = builder&.has_stamp? ? builder.stamp : stamp
      message += ";st=#{st}"

      message += ";ssc=1" if has_ssc?

      chat = builder&.has_chat_enabled? ? builder.chat_enabled : @copilot_user.chat_enabled?
      message += ";chat=1" if chat

      sn = builder&.has_snippy_enabled? ? builder.snippy_enabled : snippy_enabled?
      message += ";sn=1" if sn

      cit = builder&.has_code_citations_enabled? ? builder.code_citations_enabled : code_citations_enabled?
      message += ";cit=1" if cit

      snp = builder&.has_snippy_prompt_overlap? ? builder.snippy_prompt_overlap : snippy_prompt_overlap?
      message += ";snp=1" if snp

      malfil = builder&.has_malware_filtering? ? builder.malware_filtering : malware_filtering?
      message += ";malfil=1" if malfil

      message += ";editor_preview_features=0" if !editor_preview_features_enabled
      message += ";editor_preview_features=1" if editor_preview_features_enabled

      message += ";agent_mode=0" if agent_mode_disabled
      message += ";agent_mode=1" if !agent_mode_disabled

      message += ";agent_mode_auto_approval=0" if !agent_mode_auto_approval
      message += ";agent_mode_auto_approval=1" if agent_mode_auto_approval

      message += ";mcp=0" if !mcp_enabled
      message += ";mcp=1" if mcp_enabled

      ccr = builder&.has_code_review_enabled? ? builder.code_review_enabled : @copilot_user.copilot_code_review_enabled?
      message += ";ccr=1" if ccr

      rt = builder&.has_telemetry_enabled? ? builder.telemetry_enabled : telemetry_enabled?
      message += ";rt=1" if rt

      ft = builder&.has_fine_tuning_identifier? ? builder.fine_tuning_identifier : fine_tuning_identifier
      message += ";ft=#{ft}" if ft

      cml = (builder && builder.custom_model_list.present?) ? builder.custom_model_list : custom_model_list
      message += ";cml=#{cml.join(",")}" if cml.any?

      prompt_8k = builder&.has_prompt_8k? ? builder.prompt_8k : true
      message += ";8kp=1" if prompt_8k

      rag = builder&.has_rag_identifier? ? builder.rag_identifier : rag_identifier
      message += ";rag=#{rag}" if rag

      if builder&.has_real_ip?
        message += ";ip=#{builder.real_ip}"
      elsif include_network_information? && @headers[:real_ip].present?
        message += ";ip=#{@headers[:real_ip]&.gsub(":", "-")}"
      end

      if builder&.has_asn?
        message += ";asn=#{builder.asn}"
      elsif include_network_information? && @headers[:asn].present?
        message += ";asn=#{@headers[:asn]}"
      end

      fcv1 = builder&.has_force_copilot_codex_v1? ? builder.force_copilot_codex_v1 : force_copilot_codex_v1?
      message += ";fcv1=1" if fcv1

      message += ";ao=1" if azure_only?

      message += ";fo=1" if fedramp_only?

      # we check for feature flag and membership in the method
      message = add_ci_free_details_to_token(message)
      return message if @envelope_builder # this implies M4 extraction, where we will sign in CTS

      mac = OpenSSL::HMAC.hexdigest(HMAC_ALGORITHM, GitHub.copilot_cdn_hmac_key.to_s, message)
      "#{message}:#{mac}"
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
    def malware_filtering?
      feature_flag_from_cts(:copilot_malware_filtering)
    end

    sig { returns(T::Boolean) }
    def snippy_enabled?
      return false if snippy_blocking_disabled?
      return false if feature_flag_from_cts(:copilot_force_code_references)
      @copilot_user.block_public_code_suggestions? ||
        @copilot_user.is_partner_user?
    end

    sig { returns(T::Boolean) }
    def code_citations_enabled?
      return false if snippy_enabled?
      return false if snippy_citations_disabled?
      feature_flag_from_cts(:copilot_code_citations)
    end

    sig { returns(T::Boolean) }
    def snippy_prompt_overlap?
      feature_flag_from_cts(:copilot_snippy_prompt_overlap)
    end

    sig { returns(T::Boolean) }
    def snippy_blocking_disabled?
      snippy_blocking_globally_disabled? && !snippy_blocking_reenabled?
    end

    sig { returns(T::Boolean) }
    def snippy_blocking_globally_disabled?
      # snippy may be disabled for experiments relating to Project Heat
      feature_flag_from_cts(:copilot_snippy_blocking_disabled)
    end

    sig { returns(T::Boolean) }
    def snippy_blocking_reenabled?
      flag = feature_flag_from_cts(:copilot_snippy_blocking_reenabled)
      flag || @copilot_user.copilot_organizations.any? { |org| org.feature_flag_enabled_or_raise?(:copilot_snippy_blocking_reenabled) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def snippy_citations_disabled?
      snippy_citations_globally_disabled? && !snippy_citations_reenabled?
    end

    sig { returns(T::Boolean) }
    def snippy_citations_globally_disabled?
      # snippy may be disabled for experiments relating to Project Heat
      feature_flag_from_cts(:copilot_snippy_annotations_disabled)
    end

    sig { returns(T::Boolean) }
    def snippy_citations_reenabled?
      flag = feature_flag_from_cts(:copilot_snippy_annotations_reenabled)
      flag || @copilot_user.copilot_organizations.any? { |org| org.feature_flag_enabled_or_raise?(:copilot_snippy_annotations_reenabled) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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

    # Returns the list of custom models that the user has access to. Models
    # from a single org are sorted by the order they were created (newest
    # first). Models across multiple orgs are sorted by org ID for stable
    # ordering. Only the first custom model in this list is used for legacy
    # client, but modern clients can use any of them.
    sig { returns(T::Array[String]) }
    memoize def custom_model_list
      return [] unless FeatureFlag.vexi.enabled?(:copilot_custom_models_beta_inference_enabled, default: true)

      organizations = @copilot_user
        .copilot_organizations
        .map(&:organization_object)

      # For each Copilot Enterprise that the user has a seat through, add all
      # organizations that the user is a member of.
      user_organizations = @copilot_user.organizations
      @copilot_user.copilot_businesses.each do |business|
        next unless business.feature_flag_enabled_or_raise?(:copilot_custom_models_all_enterprise_orgs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        business.organizations.each do |organization|
          if user_organizations.include?(organization)
            organizations << organization
          end
        end
      end

      custom_models = Orca::Model.for_organizations(organizations)

      # Use the conditional access policy framework to filter models to be returned
      # based on the IP allowlist of each model's owning organization.
      if @cap_filter && feature_flag_from_cts(:copilot_custom_models_ip_cap_filter)
        if feature_flag_from_cts(:copilot_use_external_conditional_access)
          custom_models_authorized = @cap_filter.authorized_resources(custom_models, only: [:ip_allowlist, :external_conditional_access_policy])
        else
          custom_models_authorized = @cap_filter.authorized_resources(custom_models, only: :ip_allowlist)
        end
        filtered_count = custom_models.length - custom_models_authorized.length

        if filtered_count > 0
          # Apply filter, ensuring original order is preserved
          custom_models = custom_models.select do |model|
            custom_models_authorized.include?(model)
          end

          GitHub.dogstats.count(
            "copilot.custom_model.filtered",
            filtered_count,
            tags: ["filter:ip_allowlist"],
          )
        end
      end

      custom_models.map(&:resource_deployment)
    end

    sig { params(headers: T::Hash[Symbol, String]).void }
    def instrument_token_generation(headers = {})
      Copilot::Instrumenter.instrument_token_generated(
        @copilot_user,
        token_expiration,
        access_type,
        headers,
        organization_list,
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

    # This section here is so we can alias methods from the Authorizer to use EnvelopeBuilder during the M4 process
    sig { returns(String) }
    def access_type_sku
      if @envelope_builder
        type = T.must(@envelope_builder.authorizer_decision).authorative_access_type
        return :NO_ACCESS.to_s.downcase if type == :ACCESS_TYPE_INVALID
        if type.is_a?(Integer)
          type = MonolithTwirp::Copilot::Token::V1::AccessType.lookup(type)
        end
        return type.to_s.delete_prefix("ACCESS_TYPE_").to_sym.to_s
      end
      T.must(@authorizer).access_type_sku
    end

    sig { returns(T::Boolean) }
    def has_ssc?
      return T.must(@envelope_builder.authorizer_decision).is_ssc if @envelope_builder
      T.must(@authorizer).has_ssc?
    end

    sig { returns(Symbol) }
    def access_type
      if @envelope_builder
        type = T.must(@envelope_builder.authorizer_decision).authorative_access_type
        return :NO_ACCESS if type == :ACCESS_TYPE_INVALID
        if type.is_a?(Integer)
          type = MonolithTwirp::Copilot::Token::V1::AccessType.lookup(type)
        end
        return type.to_s.delete_prefix("ACCESS_TYPE_").to_sym
      end
      T.must(@authorizer).access_type
    end

    sig { returns(T::Array[String]) }
    def organization_list
      if @envelope_builder
        return @envelope_builder.organization_list.to_a if @envelope_builder.organization_list.present?
        return @copilot_user.copilot_organizations.uniq.collect(&:analytics_tracking_id)
      end
      T.must(@authorizer).organization_list
    end

    sig { returns(T::Boolean) }
    def access_allowed?
      return T.must(@envelope_builder.authorizer_decision).access_allowed if @envelope_builder
      T.must(@authorizer).access_allowed?
    end

    sig { returns(String) }
    def reason
      if @envelope_builder
        type = T.must(@envelope_builder.authorizer_decision).authorative_access_type
        return :NO_ACCESS.to_s.downcase if type == :ACCESS_TYPE_INVALID
        if type.is_a?(Integer)
          type = MonolithTwirp::Copilot::Token::V1::AccessType.lookup(type)
        end
        return type.to_s.delete_prefix("ACCESS_TYPE_").to_sym.to_s.downcase # sorry this is ugly
      end
      T.must(@authorizer).reason
    end
    # End of EnvelopeBuilder alias section

    sig { void }
    def load_envelope
      if access_allowed?
        load_token_envelope
      else
        load_error_envelope
      end
    end

    sig { void }
    def load_token_envelope
      # TODO: check if we can extract anything else that does not take advantage of the builder below
      builder = @envelope_builder
      @envelope = {
        agent_mode_auto_approval: @copilot_user.agent_mode_auto_approve_enabled?,
        annotations_enabled: builder&.has_annotations_enabled? ? builder.annotations_enabled : feature_flag_from_cts(:copilot_annotations),
        azure_only: azure_only?,
        blackbird_clientside_indexing: builder&.has_blackbird_clientside_indexing? ? builder.blackbird_clientside_indexing : feature_flag_from_cts(:blackbird_clientside_indexing),
        chat_enabled: builder&.has_chat_enabled? ? builder.chat_enabled : @copilot_user.chat_enabled?,
        chat_jetbrains_enabled: builder&.has_chat_jetbrains_enabled? ? builder.chat_jetbrains_enabled : true,
        code_quote_enabled: builder&.has_code_quote_enabled? ? builder.code_quote_enabled : @copilot_user.codequote_enabled?,
        code_review_enabled: builder&.has_code_review_enabled? ? builder.code_review_enabled : @copilot_user.copilot_code_review_enabled?,
        codesearch: builder&.has_codesearch? ? builder.codesearch : true,
        copilotignore_enabled: builder&.has_copilotignore_enabled? ? builder.copilotignore_enabled : @copilot_user.copilot_content_exclusion_enabled?,
        endpoints: builder&.has_endpoints? ? { "api" => builder.endpoints&.api, "origin-tracker" => builder.endpoints&.origin_tracker, "proxy" => builder.endpoints&.proxy, "telemetry" => builder.endpoints&.telemetry } : sku_isolation.endpoints,
        expires_at: builder&.has_expires_at? ? builder.expires_at : token_expiration,
        individual: builder&.has_individual? ? builder.individual : @copilot_user.has_cfi_access?, # this means the user is an individual user so VS can leverage that
        prompt_8k: builder&.has_prompt_8k? ? builder.prompt_8k : true,
        public_suggestions: builder&.has_public_suggestions? ? builder.public_suggestions : @copilot_user.snippy_setting,
        refresh_in: builder&.has_refresh_in? ? builder.refresh_in : token_refresh_in,
        sku: access_type_sku,
        snippy_load_test_enabled: builder&.has_snippy_load_test_enabled? ? builder.snippy_load_test_enabled : @copilot_user.snippy_load_test_enabled?,
        telemetry: builder&.has_telemetry? ? builder.telemetry : @copilot_user.telemetry_setting,
        token: builder&.has_token? ? builder.token : generate_v2_token,
        tracking_id: builder&.has_tracking_id? ? builder.tracking_id : analytics_tracking_id,
        vsc_electron_fetcher_v2: builder&.has_vsc_electron_fetcher_v2? ? builder.vsc_electron_fetcher_v2 : vsc_electron_fetcher_enabled?,
        xcode_chat: builder&.has_xcode_chat? ? builder.xcode_chat : xcode_chat_enabled?,
        xcode: builder&.has_xcode? ? builder.xcode : xcode_enabled?,
      }

      # This appears to be a disadvantage of having repeatable fields - perhaps we should investigate a different approach
      if builder && builder.organization_list.present?
        @envelope[:organization_list] = builder.organization_list.to_a
      elsif org_tracking_ids.any?
        @envelope[:organization_list] = org_tracking_ids
      end

      if builder && builder.enterprise_list.present?
        @envelope[:enterprise_list] = builder.enterprise_list.map(&:to_s)
      elsif business_list.any?
        @envelope[:enterprise_list] = business_list.collect(&:id)
      end

      if builder && builder.limited_user_quotas.present?
        @envelope[:limited_user_quotas] = builder.limited_user_quotas.to_h
      else
        @envelope[:limited_user_quotas] = feature_quotas
      end

      if builder && builder.has_limited_user_reset_date?
        @envelope[:limited_user_reset_date] = builder.limited_user_reset_date
      else
        @envelope[:limited_user_reset_date] = limited_user_reset_date
      end

      unless feature_flag_from_cts(:copilot_deprecate_user_notification)
        notification = @copilot_user.check_notifications

        if notification.present?
          editor_notification = notification.store
          @envelope[:user_notification] = notification.envelope_data if editor_notification&.persisted?
        end

        add_free_over_limits_notification
      end
    end

    sig { void }
    def load_error_envelope
      GitHub.logger.with_named_tags({
        "code.function": "load_error_envelope",
        "code.namespace": "Copilot::EnvelopeExtracted",
        "gh.user.id": @copilot_user.id,
        "gh.copilot.editor_version": @headers[:editor_version],
        "gh.copilot.editor_plugin_version": @headers[:editor_plugin_version],
        "gh.copilot.envelope.failure_reason": reason,
        "gh.copilot.envelope.api_version": @api_version,
      }) do
        @envelope = {
          message: "Resource not accessible by integration",
          can_signup_for_limited: @copilot_user.can_signup_for_limited?,
        }

        # reason is a lower case string
        case reason
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
      return message unless access_type == :FREE_LIMITED_COPILOT
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

    sig { void }
    def add_free_over_limits_notification
      return unless @copilot_user.limited_user.present?

      limited_user = T.must(@copilot_user.limited_user)
      completions_quota = limited_user.feature_quota_remaining(feature: "completions")

      return if completions_quota > 0

      message = "You've reached your monthly code completion limit. Upgrade your plan to Copilot Pro (30-day Free Trial) or wait until #{limited_user.reset_date} for your limit to reset to continue coding with GitHub Copilot."

      @envelope[:user_notification] = {
        message: add_user_to_msg(message),
        url: PLANS_PAGE,
        title: "Upgrade your plan",
        notification_id: "free_over_limits"
      }

    end

    # since editors have untrusty clocks (they aren't synced to our servers, sadly) we need
    # to include this value so that the editor can calculate client side when they should refresh
    # the token. we are making this a little less than the token_expiration/server side time
    # so that we can have a little bit of leeway
    sig { returns(Integer) }
    memoize def token_refresh_in
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
      organization_list
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
        notification_id: reason,
      }
      if reason == "revoked_coupon"
        # we are specifically not allowing these users to sign up for the limited experience
        @envelope[:can_signup_for_limited] = false
      end

      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:#{reason}", "event:shown"],
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
        notification_id: reason,
      }

      # we are specifically not allowing these users to sign up for the limited experience
      # because they are trade restricted
      @envelope[:can_signup_for_limited] = false

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, reason, @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:#{reason}", "event:shown"],
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
        notification_id: reason,
      }

      # setting this to nil so it doesn't show up
      @envelope[:can_signup_for_limited] = nil

      Copilot::Instrumenter.instrument_editor_notification_shown(@copilot_user, reason, @headers)
      GitHub.dogstats.increment(
        "copilot.notification",
        tags: ["notification_id:#{reason}", "event:shown"],
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
    def vsc_electron_fetcher_enabled?
      feature_flag_from_cts(:copilot_vsc_electron_fetcher)
    end

    sig { returns(T::Boolean) }
    def include_network_information?
      feature_flag_from_cts(:copilot_token_include_network_information)
    end

    sig { returns(T::Boolean) }
    def multiple_fine_tuning_identifiers?
      flag = :copilot_custom_models_multi_ft
      base = feature_flag_from_cts(flag)
      base || @copilot_user.copilot_businesses.all? { |biz| biz.feature_flag_enabled_or_raise?(flag) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    sig { returns(T::Boolean) }
    def xcode_enabled?
      feature_flag_from_cts(:copilot_xcode)
    end

    sig { returns(T::Boolean) }
    def xcode_chat_enabled?
      feature_flag_from_cts(:copilot_xcode_chat)
    end

    # force code completions to use the codex v1 model - needed to support special customers that need to get compliance approval for CodexV2
    # see https://github.com/github/copilot/issues/16588
    sig { returns(T::Boolean) }
    def force_copilot_codex_v1?
      base = feature_flag_from_cts(:copilot_force_completions_codex_v1)
      base || @copilot_user.copilot_organizations.any? { |org| org.feature_flag_enabled_or_raise?(:copilot_force_completions_codex_v1) } || # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @copilot_user.copilot_businesses.any? { |biz| biz.feature_flag_enabled_or_raise?(:copilot_force_completions_codex_v1) } # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    # Returns the CTS-evaluated feature flag value if present
    sig { params(flag: Symbol).returns(T::Boolean) }
    def feature_flag_from_cts(flag)
      return false unless @feature_flags

      value = @feature_flags[flag]
      return false if value.nil?

      value
    end
  end
end
