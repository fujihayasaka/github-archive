# typed: true
# frozen_string_literal: true

########################################
#### HEY FRIENDS, PLEASE READ THIS! ####
########################################
# It would be super duper cool if you  #
# could help out future you (and us)   #
# by keeping the envelopes below sorted#
# alphabetically. It makes it easier   #
# to see what's changed in the diff.   #
########################################

require "test_helper"

class Copilot::EnvelopeTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include ConditionalAccess::FilterTestHelper

  setup do
    disable_feature_flag(:copilot_revokable_access)
    disable_feature_flag(:copilot_respect_revokable_access)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    Copilot::User.any_instance.stubs(:copilot_code_review_enabled?).returns(false)
  end

  fixtures do
    @user = create(:user, analytics_tracking_id: "fake")
    @user.analytics_tracking_id = "fake"
    @user.save

    @org = create(:organization, analytics_tracking_id: "ekaf")
    @org.analytics_tracking_id = "ekaf"
    @org.save

    GitHub.copilot_cdn_hmac_key = "testkey"
  end

  context "token_refresh_in" do
    test "same for non limited users" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        sku = "free_educational"

        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)
        Copilot::User.any_instance.stubs(:copilot_code_review_enabled?).returns(true)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)
        assert_equal Copilot::TokenRefresh::TOKEN_REFRESH_IN.to_i, envelope.envelope[:refresh_in].to_i
      end
    end

    test "limited users not in the feature flag get the default" do
      freeze_time do
        limited_user = create(:copilot_limited_user, user: @user, subscribed_at: Time.now)
        Copilot.limiter_redis.set(limited_user.feature_count_key("chat"), 2)
        Copilot.limiter_redis.set(limited_user.feature_count_key("completions"), 2)
        copilot_user = Copilot::User.new(@user)
        assert copilot_user.chat_enabled? # they have quota

        copilot_user.block_public_code_suggestions!
        sku = "free_limited_copilot"

        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)
        Copilot::User.any_instance.stubs(:copilot_code_review_enabled?).returns(true)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)
        assert_equal Copilot::TokenRefresh::TOKEN_REFRESH_IN.to_i, envelope.envelope[:refresh_in].to_i
      end
    end
  end

  context "token_expiration" do
    test "same for non limited users" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        sku = "free_educational"

        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)
        Copilot::User.any_instance.stubs(:copilot_code_review_enabled?).returns(true)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal Copilot::TokenExpiration::TOKEN_EXPIRATION_SECONDS.seconds.from_now.to_i, envelope.envelope[:expires_at].to_i
      end
    end

    test "limited users not in the feature flag get the default" do
      freeze_time do
        limited_user = create(:copilot_limited_user, user: @user, subscribed_at: Time.now)
        Copilot.limiter_redis.set(limited_user.feature_count_key("chat"), 2)
        Copilot.limiter_redis.set(limited_user.feature_count_key("completions"), 2)
        copilot_user = Copilot::User.new(@user)
        assert copilot_user.chat_enabled? # they have quota

        copilot_user.block_public_code_suggestions!
        sku = "free_limited_copilot"

        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)
        Copilot::User.any_instance.stubs(:copilot_code_review_enabled?).returns(true)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)
        assert_equal Copilot::TokenExpiration::TOKEN_EXPIRATION_SECONDS.seconds.from_now.to_i, envelope.envelope[:expires_at].to_i
      end
    end

    Copilot::TokenExpiration::TOKEN_EXPIRATION_DEFAULTS.each_with_index do |step, i|
      test "limited users get #{step[:duration]} refresh_in for step #{i}" do
        freeze_time do
          enable_feature_flag(:copilot_free_token_refresh, @user)
          Copilot::LimitedUser.any_instance.stubs(:feature_quota_percentage_remaining).returns(step[:low].to_f)
          create(:copilot_limited_user, user: @user, subscribed_at: Time.now)

          copilot_user = Copilot::User.new(@user)
          assert copilot_user.chat_enabled? # they have quota

          copilot_user.block_public_code_suggestions!

          auth = Copilot::Authorizer.new(copilot_user)
          envelope = Copilot::Envelope.new(auth, Hash.new)
          assert_equal step[:duration].to_i.seconds.from_now.to_i, envelope.envelope[:expires_at].to_i
        end
      end
    end
  end

  context "#generate_v2_token" do
    test "generates expected token" do
      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461
        sku = "unknown"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        assert_equal Copilot::SKUIsolation::INDIVIDUAL,
          envelope.sku_isolation.plan

        refute envelope.snippy_enabled?
        assert envelope.telemetry_enabled?
        refute copilot_user.chat_enabled?
        known_token = "tid=fake;exp=1643080461;sku=unknown;st=dotcom;nes=0;editor_preview_features=0;rt=1;8kp=1"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end

    test "generates expected token with cfb orgs" do
      @org.add_member(@user)
      create(:copilot_seat, organization: @org, assigned_user: @user)

      freeze_time do
        copilot_user = Copilot::User.new(@user)

        expiry = 1643080461
        sku = "copilot_for_business_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        assert_equal Copilot::SKUIsolation::BUSINESS,
          envelope.sku_isolation.plan

        assert envelope.snippy_enabled?
        refute envelope.telemetry_enabled?

        known_token = "tid=fake;ol=ekaf;exp=1643080461;sku=copilot_for_business_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;8kp=1"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end

    test "generates expected token with special cfb orgs" do
      ::User.any_instance.stubs(:organization_ids).returns([Copilot::GITHUB_ORG_ID])
      @org.add_member(@user)
      create(:copilot_seat, organization: @org, assigned_user: @user)

      freeze_time do
        copilot_user = Copilot::User.new(@user)

        expiry = 1643080461
        sku = "copilot_for_business_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        assert_equal Copilot::SKUIsolation::BUSINESS,
          envelope.sku_isolation.plan

        assert envelope.snippy_enabled?
        assert envelope.telemetry_enabled?

        known_token = "tid=fake;ol=ekaf;exp=1643080461;sku=copilot_for_business_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end

    test "generates expected token with public code suggestions blocked" do
      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461
        sku = "unknown"
        copilot_user.block_public_code_suggestions!

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        assert_equal Copilot::SKUIsolation::INDIVIDUAL,
          envelope.sku_isolation.plan

        assert envelope.snippy_enabled?
        assert envelope.telemetry_enabled?

        known_token = "tid=fake;exp=1643080461;sku=unknown;st=dotcom;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end

    test "generates expected token with telemetry disabled" do
      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461
        sku = "unknown"
        copilot_user.disable_telemetry!

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp
        assert_empty envelope.custom_model_list

        assert_equal Copilot::SKUIsolation::INDIVIDUAL,
          envelope.sku_isolation.plan

        refute envelope.telemetry_enabled?

        known_token = "tid=fake;exp=1643080461;sku=unknown;st=dotcom;nes=0;editor_preview_features=0;8kp=1"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end

    test "generates expected token with a custom model" do
      @org.add_member(@user)
      create(:copilot_seat, organization: @org, assigned_user: @user)
      orca_model = create(
        :orca_model,
        organization: @org,
        resource: "resource",
        deployment: "deployment",
      )

      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal [orca_model.resource_deployment],
          envelope.custom_model_list

        parts = envelope.generate_v2_token.split(":").first
        cml = parts.to_s.split(";").find { |part| part.start_with?("cml=") }
        assert_equal "cml=resource.deployment", cml
      end
    end

    test "generates expected token with multiple custom models in the same org" do
      @org.add_member(@user)
      create(:copilot_seat, organization: @org, assigned_user: @user)
      create(:orca_model,
        organization: @org,
        resource: "resource",
        deployment: "deployment",
        created_at: 1.day.ago,
      )
      orca_model2 = create(
        :orca_model,
        organization: @org,
        resource: "resource2",
        deployment: "deployment2",
      )

      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal [orca_model2.resource_deployment],
          envelope.custom_model_list,
          "orders custom models by created_at"

        parts = envelope.generate_v2_token.split(":").first
        cml = parts.to_s.split(";").find { |part| part.start_with?("cml=") }
        assert_equal "cml=resource2.deployment2", cml
      end
    end

    test "generates expected token with custom models across multiple orgs" do
      @org.add_member(@user)
      @org2 = create(:organization)
      @org2.add_member(@user)

      create(:copilot_seat, organization: @org, assigned_user: @user)
      create(:copilot_seat, organization: @org2, assigned_user: @user)

      orca_model = create(
        :orca_model,
        organization: @org,
        resource: "resource",
        deployment: "deployment",
        created_at: 1.day.ago,
      )

      orca_model2 = create(
        :orca_model,
        organization: @org2,
        resource: "resource2",
        deployment: "deployment2",
      )

      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal [orca_model.resource_deployment, orca_model2.resource_deployment],
          envelope.custom_model_list,
          "orders orgs by ID for stability"

        parts = envelope.generate_v2_token.split(":").first
        cml = parts.to_s.split(";").find { |part| part.start_with?("cml=") }
        assert_equal "cml=resource.deployment,resource2.deployment2", cml
      end
    end

    test "includes custom models from orgs in the users copilot enterprise" do
      org1 = create(:copilot_for_business_enabled_organization)
      biz = org1.business
      org2 = create(:organization, business: biz)

      enable_feature_flag(:copilot_custom_models_all_enterprise_orgs, biz)

      org1.add_member(@user)
      org2.add_member(@user)

      create(:copilot_seat, organization: org1, assigned_user: @user)

      orca_model = create(
        :orca_model,
        organization: org2,
        resource: "resource",
        deployment: "deployment",
        created_at: 1.day.ago,
      )

      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal [orca_model.resource_deployment],
          envelope.custom_model_list,
          "includes model from org in the user's copilot enterprise"

        parts = envelope.generate_v2_token.split(":").first
        cml = parts.to_s.split(";").find { |part| part.start_with?("cml=") }
        assert_equal "cml=resource.deployment", cml
      end
    end

    test "generates expected token with custom models across multiple orgs with authorizing cap filter" do
      enable_feature_flag(:copilot_custom_models_ip_cap_filter, @user)

      @org.add_member(@user)
      @org2 = create(:organization)
      @org2.add_member(@user)

      create(:copilot_seat, organization: @org, assigned_user: @user)
      create(:copilot_seat, organization: @org2, assigned_user: @user)

      orca_model = create(
        :orca_model,
        organization: @org,
        resource: "resource",
        deployment: "deployment",
        created_at: 1.day.ago,
      )

      orca_model2 = create(
        :orca_model,
        organization: @org2,
        resource: "resource2",
        deployment: "deployment2",
      )

      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new, cap_authorizing_filter)

        assert_equal [orca_model.resource_deployment, orca_model2.resource_deployment],
          envelope.custom_model_list,
          "all models are accessible based on cap filtering"

        parts = envelope.generate_v2_token.split(":").first
        cml = parts.to_s.split(";").find { |part| part.start_with?("cml=") }
        assert_equal "cml=resource.deployment,resource2.deployment2", cml
        assert_equal 0, GitHub.dogstats.counts("copilot.custom_model.filtered").length, "No metrics expected"
      end
    end

    test "generates expected token without custom models if using unauthorizing cap filter" do
      enable_feature_flag(:copilot_custom_models_ip_cap_filter, @user)

      @org.add_member(@user)
      @org2 = create(:organization)
      @org2.add_member(@user)

      create(:copilot_seat, organization: @org, assigned_user: @user)
      create(:copilot_seat, organization: @org2, assigned_user: @user)

      create(
        :orca_model,
        organization: @org,
        resource: "resource",
        deployment: "deployment",
        created_at: 1.day.ago,
      )

      create(
        :orca_model,
        organization: @org2,
        resource: "resource2",
        deployment: "deployment2",
      )

      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new, cap_unauthorizing_filter)

        assert_empty envelope.custom_model_list, "custom models list is filtered to empty"

        parts = envelope.generate_v2_token.split(":").first
        cml = parts.to_s.split(";").find { |part| part.start_with?("cml=") }
        assert_nil cml
        assert_equal 1, GitHub.dogstats.counts("copilot.custom_model.filtered").length, "Expected filtering to happen"
        assert_equal 2, GitHub.dogstats.counts("copilot.custom_model.filtered").sum(&:value), "Expected 2 models filtered"
      end
    end

    test "generates expected token with restricted custom model list after cap filtering" do
      enable_feature_flag(:copilot_custom_models_ip_cap_filter, @user)

      @org.add_member(@user)
      @org2 = create(:organization)
      @org2.add_member(@user)

      create(:copilot_seat, organization: @org, assigned_user: @user)
      create(:copilot_seat, organization: @org2, assigned_user: @user)

      create(
        :orca_model,
        organization: @org,
        resource: "resource",
        deployment: "deployment",
        created_at: 1.day.ago,
      )

      orca_model2 = create(
        :orca_model,
        organization: @org2,
        resource: "resource2",
        deployment: "deployment2",
      )

      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new, cap_authorizing_filter([orca_model2]))

        assert_equal [orca_model2.resource_deployment],
          envelope.custom_model_list,
          "only one model is accessible based on cap filtering"

        parts = envelope.generate_v2_token.split(":").first
        cml = parts.to_s.split(";").find { |part| part.start_with?("cml=") }
        assert_equal "cml=resource2.deployment2", cml
        assert_equal 1, GitHub.dogstats.counts("copilot.custom_model.filtered").length, "Expected filtering to happen"
        assert_equal 1, GitHub.dogstats.counts("copilot.custom_model.filtered").sum(&:value), "Expected 1 model filtered"
      end
    end

    test "includes stamp and disables telemetry on Proxima stamps" do
      on_multi_tenant_enterprise stamp: "staff-wus2-01" do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        copilot_user.allow_public_code_suggestions!

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal "staff-wus2-01", envelope.stamp

        refute envelope.telemetry_enabled?
        refute_includes envelope.generate_v2_token, ";rt=1"
        assert_includes envelope.generate_v2_token, ";st=staff-wus2-01"
      end
    end

    test "generates expected token with 8k prompts" do
      freeze_time do
        copilot_user = Copilot::User.new(@user)
        expiry = 1643080461
        sku = "unknown"
        copilot_user.disable_telemetry!

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        refute envelope.telemetry_enabled?

        known_token = "tid=fake;exp=1643080461;sku=unknown;st=dotcom;nes=0;editor_preview_features=0;8kp=1"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end

    test "generates expected token with enterprise cfb orgs" do
      org = create(:copilot_for_business_credit_card_enabled_organization)
      org.analytics_tracking_id = "ekafaa"
      org.save
      user = create(:user)
      user.analytics_tracking_id = "reallyfake"
      user.save
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)

      freeze_time do
        copilot_user = Copilot::User.new(user)

        expiry = 1643080461
        sku = "copilot_for_business_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "reallyfake"
        assert_equal "dotcom", envelope.stamp

        assert_equal Copilot::SKUIsolation::BUSINESS,
          envelope.sku_isolation.plan

        assert envelope.snippy_enabled?
        refute envelope.telemetry_enabled?

        known_token = "tid=reallyfake;ol=ekafaa;exp=1643080461;sku=copilot_for_business_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;8kp=1"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end
  end

  context "happy_path" do
    test "generates a complete envelope" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)
        Copilot::User.any_instance.stubs(:copilot_code_review_enabled?).returns(true)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;ccr=1;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: true,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates an 8k prompt envelope" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates an envelope with a user with snippy enabled" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        copilot_user.block_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)
        assert auth.access_allowed?
        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal @org.analytics_tracking_id, "ekaf"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: false,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates an envelope with a user with restricted telemetry disabled" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        copilot_user.disable_telemetry!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "disabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "codequote enabled and annotations" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        enable_feature_flag(:copilot_annotations, @user)

        copilot_user = Copilot::User.new(@user)
        copilot_user.allow_public_code_suggestions!
        copilot_user.disable_telemetry!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first


        assert_nil envelope.generate_v2_token.index("sn=1")
        assert envelope.envelope[:annotations_enabled]
        assert envelope.envelope[:code_quote_enabled]
      end
    end

    test "snippy load test enabled" do
      enable_feature_flag(:copilot_snippy_load_test_enabled)
      create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
      copilot_user = Copilot::User.new(@user)

      enable_feature_flag(:copilot_force_code_references)
      copilot_user.block_public_code_suggestions!
      expiry = 1643080461
      sku = "free_educational"

      Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
      Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

      auth = Copilot::Authorizer.new(copilot_user)
      envelope = Copilot::Envelope.new(auth, Hash.new)
      assert auth.access_allowed?
      assert_equal auth.access_type_sku, sku
      assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
      assert_equal @org.analytics_tracking_id, "ekaf"
      assert_equal "dotcom", envelope.stamp

      assert copilot_user.snippy_load_test_enabled?
      assert envelope.envelope[:snippy_load_test_enabled]
    end

    test "force codequote enabled" do
      create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
      copilot_user = Copilot::User.new(@user)

      enable_feature_flag(:copilot_force_code_references)
      copilot_user.block_public_code_suggestions!
      expiry = 1643080461
      sku = "free_educational"

      Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
      Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

      auth = Copilot::Authorizer.new(copilot_user)
      envelope = Copilot::Envelope.new(auth, Hash.new)
      assert auth.access_allowed?
      assert_equal auth.access_type_sku, sku
      assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
      assert_equal @org.analytics_tracking_id, "ekaf"
      assert_equal "dotcom", envelope.stamp

      refute envelope.snippy_enabled?
      assert_nil envelope.generate_v2_token.index("sn=1")
      assert envelope.envelope[:code_quote_enabled]
    end

    test "snippy prompt overlap feature enabled" do
      create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
      copilot_user = Copilot::User.new(@user)

      enable_feature_flag(:copilot_snippy_prompt_overlap)
      copilot_user.block_public_code_suggestions!
      expiry = 1643080461
      sku = "free_educational"

      Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
      Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

      auth = Copilot::Authorizer.new(copilot_user)
      envelope = Copilot::Envelope.new(auth, Hash.new)
      assert auth.access_allowed?
      assert_equal auth.access_type_sku, sku
      assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
      assert_equal @org.analytics_tracking_id, "ekaf"
      assert_equal "dotcom", envelope.stamp
      known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;sn=1;snp=1;nes=0;editor_preview_features=0;rt=1;8kp=1"
      assert_equal known_token, envelope.generate_v2_token.split(":").first
      assert envelope.snippy_prompt_overlap?
    end

    test "malware filtering feature enabled" do
      create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
      copilot_user = Copilot::User.new(@user)

      enable_feature_flag(:copilot_malware_filtering)
      copilot_user.block_public_code_suggestions!
      expiry = 1643080461
      sku = "free_educational"

      Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
      Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

      auth = Copilot::Authorizer.new(copilot_user)
      envelope = Copilot::Envelope.new(auth, Hash.new)
      assert auth.access_allowed?
      assert_equal auth.access_type_sku, sku
      assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
      assert_equal @org.analytics_tracking_id, "ekaf"
      assert_equal "dotcom", envelope.stamp
      known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;sn=1;malfil=1;nes=0;editor_preview_features=0;rt=1;8kp=1"
      assert_equal known_token, envelope.generate_v2_token.split(":").first
      assert envelope.malware_filtering?
    end

    test "malware filtering feature disabled" do
      create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
      copilot_user = Copilot::User.new(@user)

      disable_feature_flag(:copilot_malware_filtering)
      copilot_user.block_public_code_suggestions!
      expiry = 1643080461
      sku = "free_educational"

      Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
      Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

      auth = Copilot::Authorizer.new(copilot_user)
      envelope = Copilot::Envelope.new(auth, Hash.new)
      assert auth.access_allowed?
      assert_equal auth.access_type_sku, sku
      assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
      assert_equal @org.analytics_tracking_id, "ekaf"
      assert_equal "dotcom", envelope.stamp
      known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1"
      assert_equal known_token, envelope.generate_v2_token.split(":").first
      assert !envelope.malware_filtering?
    end

    test "code citations enabled" do
      create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
      copilot_user = Copilot::User.new(@user)

      enable_feature_flag(:copilot_code_citations)
      copilot_user.allow_public_code_suggestions!
      expiry = 1643080461
      sku = "free_educational"

      Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
      Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

      auth = Copilot::Authorizer.new(copilot_user)
      envelope = Copilot::Envelope.new(auth, Hash.new)
      assert auth.access_allowed?
      assert_equal auth.access_type_sku, sku
      assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
      assert_equal @org.analytics_tracking_id, "ekaf"
      assert_equal "dotcom", envelope.stamp
      known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;cit=1;nes=0;editor_preview_features=0;rt=1;8kp=1"
      assert_equal known_token, envelope.generate_v2_token.split(":").first
      assert envelope.code_citations_enabled?
    end

    test "code citations disabled" do
      create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
      copilot_user = Copilot::User.new(@user)

      enable_feature_flag(:copilot_code_citations)
      copilot_user.block_public_code_suggestions!
      expiry = 1643080461
      sku = "free_educational"

      Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
      Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

      auth = Copilot::Authorizer.new(copilot_user)
      envelope = Copilot::Envelope.new(auth, Hash.new)
      assert auth.access_allowed?
      assert_equal auth.access_type_sku, sku
      assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
      assert_equal @org.analytics_tracking_id, "ekaf"
      assert_equal "dotcom", envelope.stamp
      known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1"
      assert_equal known_token, envelope.generate_v2_token.split(":").first
      assert !envelope.code_citations_enabled?
    end

    test "chat enabled" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        copilot_user.enable_chat!
        copilot_user.allow_public_code_suggestions!
        copilot_user.disable_telemetry!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "disabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "editor chat enabled" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        copilot_user.allow_public_code_suggestions!
        copilot_user.disable_telemetry!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "disabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "fine tuning enabled" do
      @org.add_member(@user)
      Copilot::Organization.new(@org).private_telemetry_enabled!
      create(:copilot_seat, organization: @org, assigned_user: @user)

      freeze_time do
        copilot_user = Copilot::User.new(@user)

        expiry = 1643080461
        sku = "copilot_for_business_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        assert envelope.snippy_enabled?
        refute envelope.telemetry_enabled?

        known_token = "tid=fake;ol=ekaf;exp=1643080461;sku=copilot_for_business_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;ft=org_ekaf;8kp=1"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end

    test "fine tuning enabled with multiple ft identifiers" do
      enable_feature_flag(:copilot_custom_models_multi_ft, @user)

      @org.add_member(@user)

      org2 = create(:organization)
      org2.update! analytics_tracking_id: "org2"
      org2.add_member(@user)

      Copilot::Organization.new(@org).private_telemetry_enabled!
      Copilot::Organization.new(org2).private_telemetry_enabled!

      create(:copilot_seat, organization: @org, assigned_user: @user)
      create(:copilot_seat, organization: org2, assigned_user: @user)

      freeze_time do
        copilot_user = Copilot::User.new(@user)

        expiry = 1643080461
        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal "org_ekaf,org_org2",
          envelope.fine_tuning_identifier

        parts = T.must(envelope.generate_v2_token.split(":").first).split(";")

        assert_equal "ft=org_ekaf,org_org2",
          parts.find { _1.start_with?("ft=") }
      end
    end

    test "retrieval enabled" do
      @org.add_member(@user)
      enable_feature_flag(:copilot_retrieval_alpha_org, @org)
      create(:copilot_seat, organization: @org, assigned_user: @user)

      freeze_time do
        copilot_user = Copilot::User.new(@user)

        expiry = 1643080461
        sku = "copilot_for_business_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;ol=ekaf;exp=1643080461;sku=copilot_for_business_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;8kp=1;rag=org_ekaf"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end

    test "copilotignore enabled for always on orgs" do
      freeze_time do
        seat = create(:copilot_seat)
        user = seat.assigned_user
        org = seat.seat_assignment.owner
        Copilot::User.any_instance.stubs(:check_notifications).returns(nil)
        copilot_user = Copilot::User.new(user)
        create(:copilot_content_exclusion_configuration, :organization, resource: org)

        copilot_user.allow_public_code_suggestions!
        copilot_user.disable_telemetry!
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal "dotcom", envelope.stamp

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: false,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: true,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          enterprise_list: [org.business.id],
          expires_at: expiry,
          individual: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
          nes_enabled: false,
          organization_list: [org.analytics_tracking_id],
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: "copilot_for_business_seat",
          snippy_load_test_enabled: false,
          telemetry: "disabled",
          token: envelope.generate_v2_token,
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
        }
        assert_equal expected, envelope.envelope.sort.to_h
      end
    end

    test "generates an envelope for a user in multiple businesses" do
      freeze_time do
        org1 = create(:copilot_for_business_enabled_organization)
        org1.analytics_tracking_id = "tuna"
        org1.save
        org2 = create(:copilot_for_business_enabled_organization)
        org2.analytics_tracking_id = "tortilla"
        org2.save

        user = create(:user)
        user.analytics_tracking_id = "fish"
        user.save
        org1.add_member(user)
        org2.add_member(user)

        create(:copilot_seat, organization: org1, assigned_user: user)
        create(:copilot_seat, organization: org2, assigned_user: user)

        copilot_user = Copilot::User.new(user)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "copilot_for_business_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, user.analytics_tracking_id
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fish;ol=tuna,tortilla;exp=1643080461;sku=copilot_for_business_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: copilot_user.codequote_enabled?,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          enterprise_list: [org1.business.id, org2.business.id],
          expires_at: expiry,
          individual: false,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "disabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
        }
        assert_subset_hash expected, envelope.envelope
      end
    end

    test "generates an envelope for a user in multiple businesses and one of them is magical" do
      freeze_time do
        org1 = create(:copilot_for_business_enabled_organization)
        org1.analytics_tracking_id = "tuna"
        org1.save
        org2 = create(:copilot_for_business_enabled_organization)
        org2.analytics_tracking_id = "tortilla"
        org2.save

        user = create(:user)
        user.analytics_tracking_id = "fish"
        user.save
        org1.add_member(user)
        org2.add_member(user)

        create(:copilot_seat, organization: org1, assigned_user: user)
        create(:copilot_seat, organization: org2, assigned_user: user)

        copilot_user = Copilot::User.new(user)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "copilot_for_business_seat"
        ::User.any_instance.stubs(:organization_ids).returns([org1.id, org2.id, Copilot::GITHUB_ORG_ID])
        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, user.analytics_tracking_id
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fish;ol=tuna,tortilla;exp=1643080461;sku=copilot_for_business_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: copilot_user.codequote_enabled?,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          enterprise_list: [org1.business.id, org2.business.id],
          expires_at: expiry,
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
        }
        assert_subset_hash expected, envelope.envelope
      end
    end

    test "enterprise team user with chat enabled" do
      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        seat_assignment.convert_to_seats

        copilot_business = Copilot::Business.new(seat_assignment.owner)
        copilot_business.enable_chat!
        seat = seat_assignment.seats.first
        user = seat.assigned_user
        user.analytics_tracking_id = "star"
        user.save

        copilot_user = Copilot::User.new(user)

        expiry = 1643080461
        sku = "copilot_standalone_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "star"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=star;exp=1643080461;sku=copilot_standalone_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: copilot_user.annotations_enabled?,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: copilot_user.codequote_enabled?,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          enterprise_list: [seat_assignment.owner.id],
          expires_at: expiry,
          individual: false,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "disabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          user_notification: {
            message: "The enterprise #{seat_assignment.owner.slug} has granted you access to GitHub Copilot.",
            url: "https://github.com/settings/copilot?editor={EDITOR}",
            title: "Copilot Settings",
            notification_id: "copilot_enterprise_seat_added_#{seat_assignment.owner.id}",
          },
          vsc_electron_fetcher_v2: false,
          xcode: false,
          xcode_chat: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope.sort.to_h
      end
    end

    test "does not return user_notification if not saved in DB" do
      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        seat_assignment.convert_to_seats

        copilot_business = Copilot::Business.new(seat_assignment.owner)
        copilot_business.enable_chat!
        seat = seat_assignment.seats.first
        user = seat.assigned_user
        user.analytics_tracking_id = "star"
        user.save

        copilot_user = Copilot::User.new(user)

        expiry = 1643080461
        sku = "copilot_standalone_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)
        Copilot::EditorNotification.stubs(:create).returns(Copilot::EditorNotification.new)
        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "star"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=star;exp=1643080461;sku=copilot_standalone_seat;st=dotcom;ssc=1;chat=1;sn=1;nes=0;editor_preview_features=0;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: copilot_user.annotations_enabled?,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: copilot_user.codequote_enabled?,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          enterprise_list: [seat_assignment.owner.id],
          expires_at: expiry,
          individual: false,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "disabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode: false,
          xcode_chat: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope.sort.to_h
      end
    end

    test "generates envelope with copilot JB IDE chat public beta limit" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        disable_feature_flag(:copilot_annotations)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates envelope with vsc electron fetcher enabled" do
      freeze_time do
        enable_feature_flag(:copilot_vsc_electron_fetcher, @user)
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        disable_feature_flag(:copilot_annotations)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: true,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates envelope with xcode enabled" do
      freeze_time do
        enable_feature_flag(:copilot_xcode, @user)
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        disable_feature_flag(:copilot_annotations)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: true,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates envelope with xcode chat enabled" do
      freeze_time do
        enable_feature_flag(:copilot_xcode_chat, @user)
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        disable_feature_flag(:copilot_annotations)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: true,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates envelope with codesearch enabled" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true)
        copilot_user = Copilot::User.new(@user)
        disable_feature_flag(:copilot_annotations)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "copilot_enterprise_seat"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)
        Copilot::Authorizer.any_instance.stubs(:has_cfe_access?).returns(true)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=copilot_enterprise_seat;st=dotcom;chat=1;nes=0;editor_preview_features=0;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates envelope with nes enabled" do
      freeze_time do
        enable_feature_flag(:copilot_next_edit_suggestions, @user)
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;editor_preview_features=1;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: true,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates envelope with ip and ASN if the flag is enabled" do
      freeze_time do
        enable_feature_flag(:copilot_next_edit_suggestions, @user)
        enable_feature_flag(:copilot_token_include_network_information, @user)

        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, { real_ip: "192.168.0.1", asn: "AS13335" })

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;editor_preview_features=1;rt=1;8kp=1;ip=192.168.0.1;asn=AS13335"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: true,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates envelope without ip and ASN keys if the flag is enabled but the headers are missing" do
      freeze_time do
        enable_feature_flag(:copilot_next_edit_suggestions, @user)
        enable_feature_flag(:copilot_token_include_network_information, @user)

        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, {})

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;editor_preview_features=1;rt=1;8kp=1"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: true,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates envelope with properly escaped ipv6 address if the flag is enabledf" do
      freeze_time do
        enable_feature_flag(:copilot_next_edit_suggestions, @user)
        enable_feature_flag(:copilot_token_include_network_information, @user)

        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)

        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, { real_ip: "2001:0000:130F:0000:0000:09C0:876A:130B", asn: "AS13335" })

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;editor_preview_features=1;rt=1;8kp=1;ip=2001-0000-130F-0000-0000-09C0-876A-130B;asn=AS13335"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: true,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end
  end

  context "limited_users" do
    test "generates a complete envelope for a subscribed limited user with chat and completions quota" do
      travel_to Time.new(2022, 1, 1, 0, 0, 0) do
        limited_user = create(:copilot_limited_user, user: @user, subscribed_at: Time.now)
        Copilot.limiter_redis.set(limited_user.feature_count_key("chat"), 492)
        Copilot.limiter_redis.set(limited_user.feature_count_key("completions"), 1992)
        copilot_user = Copilot::User.new(@user)
        assert copilot_user.chat_enabled? # they have quota

        copilot_user.block_public_code_suggestions!
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        sku = auth.access_type_sku
        envelope = Copilot::Envelope.new(auth, Hash.new)

        known_token = "tid=fake;exp=1643080461;sku=#{sku};st=dotcom;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1;cq=8;rd=1643673600"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: false,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          limited_user_quotas: {
            "chat" => 8,
            "completions" => 8,
          },
          limited_user_reset_date: 1643673600,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
        }

        assert_equal expected, envelope.envelope
      end
    end

    test "generates a complete envelope for a subscribed limited user with chat quota but no completions quota" do
      travel_to Time.new(2022, 1, 1, 0, 0, 0) do
        limited_user = create(:copilot_limited_user, user: @user, subscribed_at: Time.now)
        Copilot.limiter_redis.set(limited_user.feature_count_key("chat"), 2)
        Copilot.limiter_redis.set(limited_user.feature_count_key("completions"), 2000)
        copilot_user = Copilot::User.new(@user)
        assert copilot_user.chat_enabled? # they have quota

        copilot_user.block_public_code_suggestions!
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        sku = auth.access_type_sku
        envelope = Copilot::Envelope.new(auth, Hash.new)

        known_token = "tid=fake;exp=1643080461;sku=#{sku};st=dotcom;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1;cq=0;rd=1643673600"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        message = "You've reached your monthly code completion limit. Upgrade your plan to Copilot Pro (30-day Free Trial) or wait until #{limited_user.reset_date} for your limit to reset to continue coding with GitHub Copilot."

        error_details = {
          url: Copilot::Envelope::PLANS_PAGE,
          message: "#{message} You are currently logged in as #{@user.login}.",
          title: "Upgrade your plan",
          notification_id: "free_over_limits",
        }

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: false,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          limited_user_quotas: {
            "chat" => 498,
            "completions" => 0,
          },
          limited_user_reset_date: 1643673600,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          user_notification: error_details,
        }

        assert_equal expected, envelope.envelope
      end
    end

    test "generates a complete envelope for a subscribed limited user with no chat quota but completions quota" do
      travel_to Time.new(2022, 1, 1, 0, 0, 0) do
        limited_user = create(:copilot_limited_user, user: @user, subscribed_at: Time.now)
        Copilot.limiter_redis.set(limited_user.feature_count_key("chat"), 500)
        Copilot.limiter_redis.set(limited_user.feature_count_key("completions"), 1992)
        copilot_user = Copilot::User.new(@user)
        assert copilot_user.chat_enabled? # they have quota

        copilot_user.block_public_code_suggestions!
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        sku = auth.access_type_sku
        envelope = Copilot::Envelope.new(auth, Hash.new)

        known_token = "tid=fake;exp=1643080461;sku=#{sku};st=dotcom;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1;cq=8;rd=1643673600"

        assert_equal known_token, envelope.generate_v2_token.split(":").first

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: false,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          limited_user_quotas: {
            "chat" => 0,
            "completions" => 8,
          },
          limited_user_reset_date: 1643673600,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "enabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: "#{known_token}:#{encode_token(known_token)}",
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
        }

        assert_equal expected, envelope.envelope
      end
    end

    test "generates an error envelope for a subscribed limited user with no chat and completions quota" do
      travel_to Time.new(2022, 1, 1, 0, 0, 0) do
        limited_user = create(:copilot_limited_user, user: @user, subscribed_at: Time.now)
        Copilot.limiter_redis.set(limited_user.feature_count_key("chat"), 500)
        Copilot.limiter_redis.set(limited_user.feature_count_key("completions"), 2000)

        copilot_user = Copilot::User.new(@user)
        assert copilot_user.chat_enabled? # even though they do not have quota, it's still configured enabled

        copilot_user.block_public_code_suggestions!
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        message = "You've reached your monthly code completion limit. Upgrade your plan to Copilot Pro (30-day Free Trial) or wait until #{limited_user.reset_date} for your limit to reset to continue coding with GitHub Copilot."

        error_details = {
          url: Copilot::Envelope::PLANS_PAGE,
          message: "#{message} You are currently logged in as #{@user.login}.",
          title: "Upgrade your plan",
          notification_id: "free_over_limits",
        }

        assert_equal error_details, envelope.envelope[:user_notification]
      end
    end

    test "generates an error envelope for a subscribed limited user without snippy configured" do
      create(:copilot_limited_user, user: @user, subscribed_at: Time.now)
      Copilot::LimitedUser.any_instance.stubs(:quotas_remaining).returns({ chat: 50, completions: 0 })
      Copilot::LimitedUser.any_instance.stubs(:feature_allowed?).with(feature: "chat").returns(true)
      Copilot::LimitedUser.any_instance.stubs(:feature_allowed?).with(feature: "completions").returns(false)
      Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(false)
      copilot_user = Copilot::User.new(@user)
      assert copilot_user.chat_enabled? # they have quota

      travel_to Time.new(2022, 1, 1, 0, 0, 0) do
        auth = Copilot::Authorizer.new(copilot_user)
        refute auth.access_allowed?
        envelope = Copilot::Envelope.new(auth, Hash.new)
        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: Copilot::Envelope::SETTINGS_PAGE,
            message: "Your Copilot experience is not fully configured, complete your setup. You are currently logged in as #{@user.login}.",
            title: "Copilot Settings",
            notification_id: "snippy_not_configured"
          },
          can_signup_for_limited: false,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "generates expected token for subscribed limited user with pcs blocked and quota" do
      travel_to Time.new(2022, 1, 1, 0, 0, 0) do
        limited_user = create(:copilot_limited_user, user: @user, subscribed_at: Time.now)
        Copilot.limiter_redis.set(limited_user.feature_count_key("chat"), 1)
        Copilot.limiter_redis.set(limited_user.feature_count_key("completions"), 2)
        copilot_user = Copilot::User.new(@user)
        assert copilot_user.chat_enabled? # they have quota

        copilot_user.block_public_code_suggestions!
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, "free_limited_copilot"
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        assert_equal Copilot::SKUIsolation::INDIVIDUAL,
          envelope.sku_isolation.plan

        quota_remaining = limited_user.feature_quota_remaining(feature: "completions")
        known_token = "tid=fake;exp=1643080461;sku=free_limited_copilot;st=dotcom;chat=1;sn=1;nes=0;editor_preview_features=0;rt=1;8kp=1;cq=#{quota_remaining};rd=1643673600"
        assert_equal known_token, envelope.generate_v2_token.split(":").first
      end
    end
  end

  context "enterprise_teams can have settings too" do
    context "code_quote_enabled" do
      test "returns true based on business setting" do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        assignment.convert_to_seats

        copilot_business = Copilot::Business.new(assignment.owner)
        copilot_business.allow_public_code_suggestions!

        seat = assignment.seats.first
        user = seat.assigned_user
        assert Copilot::User.new(user).codequote_enabled?
      end

      test "returns false based on business setting" do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        assignment.convert_to_seats

        Copilot::Business.new(assignment.owner).block_public_code_suggestions!

        seat = assignment.seats.first
        user = seat.assigned_user

        assert Copilot::User.new(user).block_public_code_suggestions?
      end
    end

    context "copilot_content_exclusion_enabled" do
      test "this will be false for standalone businesses for a while" do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        assignment.convert_to_seats

        seat = assignment.seats.first
        user = seat.assigned_user

        refute Copilot::User.new(user).copilot_content_exclusion_enabled?
      end
    end

    context "public_suggestions" do
      test "returns true based on business setting" do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        assignment.convert_to_seats
        Copilot::Business.new(assignment.owner).allow_public_code_suggestions!

        seat = assignment.seats.first
        user = seat.assigned_user

        assert Copilot::User.new(user).allow_public_code_suggestions?
        assert_equal "disabled", Copilot::User.new(user).snippy_setting
      end

      test "returns false based on business setting" do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        assignment.convert_to_seats
        Copilot::Business.new(assignment.owner).block_public_code_suggestions!

        seat = assignment.seats.first
        user = seat.assigned_user

        assert Copilot::User.new(user).block_public_code_suggestions?
        assert_equal "enabled", Copilot::User.new(user).snippy_setting
      end
    end

    context "telemetry" do
      test "this will be false for standalone businesses because they are cfb" do
        assignment = create(:copilot_seat_assignment, :enterprise_team)
        assignment.convert_to_seats

        seat = assignment.seats.first
        user = seat.assigned_user

        refute Copilot::User.new(user).telemetry_enabled?
      end
    end
  end

  context "errors" do
    test "default error" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      freeze_time do
        Copilot::User.any_instance.stubs(:can_signup_for_limited?).returns(true)
        auth = Copilot::Authorizer.new(copilot_user)
        Copilot::Authorizer.any_instance.stubs(:access_allowed?).returns(false)
        Copilot::Authorizer.any_instance.stubs(:reason).returns("no_access")

        envelope = Copilot::Envelope.new(auth, Hash.new)
        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: Copilot::Envelope::SIGNUP_PAGE,
            message: "No access to GitHub Copilot found. You are currently logged in as #{user.login}.",
            title: "Sign up for GitHub Copilot",
            notification_id: "no_copilot_access",
          },
          can_signup_for_limited: true,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "emu error" do
      user = create(:emu)
      copilot_user = Copilot::User.new(user)

      freeze_time do
        auth = Copilot::Authorizer.new(copilot_user)
        Copilot::Authorizer.any_instance.stubs(:access_allowed?).returns(false)
        Copilot::Authorizer.any_instance.stubs(:reason).returns("enterprise_managed")
        envelope = Copilot::Envelope.new(auth, Hash.new)
        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            message: "Please contact your enterprise admin to enable your managed account for Copilot Business. You are currently logged in as #{user.login}.",
            url: "https://github.com",
            title: "OK", # this is what the button says in the editor
            notification_id: "enterprise_managed_user_account",
          },
          can_signup_for_limited: false,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "feature flag blocked" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      copilot_user.administrative_block!(create(:user), "reason")
      user.reload
      copilot_user = Copilot::User.new(user)

      freeze_time do
        auth = Copilot::Authorizer.new(copilot_user)
        refute auth.access_allowed?
        envelope = Copilot::Envelope.new(auth, Hash.new)
        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: Copilot::Envelope::SUPPORT_PAGE,
            message: "Contact Support. You are currently logged in as #{user.login}.",
            title: "Contact Support",
            notification_id: "feature_flag_blocked",
          },
          can_signup_for_limited: false,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "subscription_ended" do
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)

      create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_monthly_product_uuid,
        free_trial_ends_on: 10.days.ago,
        quantity: 0
      )

      copilot_user = Copilot::User.new(user)

      freeze_time do
        auth = Copilot::Authorizer.new(copilot_user)
        refute auth.access_allowed?
        envelope = Copilot::Envelope.new(auth, Hash.new)

        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: "https://github.com/settings/copilot?editor={EDITOR}",
            message: "Thank you for using GitHub Copilot. Your subscription has ended. You are currently logged in as #{copilot_user.user_object.login}.",
            title: "Copilot Settings",
            notification_id: "subscription_ended"
          },
          can_signup_for_limited: true,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "spammy_user" do
      copilot_user = Copilot::User.new(@user)

      freeze_time do
        Copilot::Authorizer.any_instance.stubs(:access_allowed?).returns(false)
        Copilot::Authorizer.any_instance.stubs(:reason).returns("spammy_user")

        auth = Copilot::Authorizer.new(copilot_user)
        refute auth.access_allowed?
        envelope = Copilot::Envelope.new(auth, Hash.new)

        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: Copilot::Envelope::SUPPORT_PAGE,
            message: "Contact Support. You are currently logged in as #{copilot_user.user_object.login}.",
            title: "Contact Support",
            notification_id: "spammy_user",
          },
          can_signup_for_limited: false,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "billing locked" do
      user = create(:user)
      user.disable!
      copilot_user = Copilot::User.new(user)

      freeze_time do
        Copilot::Authorizer.any_instance.stubs(:access_allowed?).returns(false)
        Copilot::Authorizer.any_instance.stubs(:reason).returns("billing_locked")

        auth = Copilot::Authorizer.new(copilot_user)
        refute auth.access_allowed?
        envelope = Copilot::Envelope.new(auth, Hash.new)

        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: Copilot::Envelope::BILLING_SETTINGS_PAGE,
            message: "Your account's billing is currently locked because recent account charges have failed. Please check the 'Billing & plans' section in your settings. You are currently logged in as #{copilot_user.user_object.login}.",
            title: "Billing Settings",
            notification_id: "billing_locked",
          },
          can_signup_for_limited: false,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "trade_restricted_error" do
      copilot_user = Copilot::User.new(create(:user))
      context = Context.new
      context.push(country_code: "RU")
      context.push(region: "55")
      context.push(region_name: "Moscow?")

      freeze_time do
        auth = Copilot::Authorizer.new(copilot_user, context)
        refute auth.access_allowed?
        envelope = Copilot::Envelope.new(auth, Hash.new)
        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: Copilot::COPILOT_TRADE_CONTROLS_DOCUMENTATION,
            message: "At this time, Copilot is not available in your location. You are currently logged in as #{copilot_user.user_object.login}.",
            title: "Copilot Unavailable",
            notification_id: "trade_restricted_country",
          },
          can_signup_for_limited: false,
        }
        assert_equal expected, envelope.envelope
      end
    end

    test "expired_coupon" do
      Copilot::User.any_instance.stubs(:can_signup_for_limited?).returns(true)
      Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
      Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
      free_user = create(
        :copilot_free_user,
        :educational_redeemed,
        user: create(:credit_card_user),
        subscribed: true,
      )
      user = free_user.user
      user.expire_active_coupon
      user.reload
      free_user.destroy

      copilot_user = Copilot::User.new(user)

      freeze_time do
        auth = Copilot::Authorizer.new(copilot_user)
        refute auth.access_allowed?
        envelope = Copilot::Envelope.new(auth, Hash.new)

        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: Copilot::Envelope::SIGNUP_PAGE,
            message: "No access to GitHub Copilot found. You are currently logged in as #{copilot_user.user_object.login}.",
            title: "Sign up for GitHub Copilot",
            notification_id: "expired_coupon",
          },
          can_signup_for_limited: true,
        }
        assert_equal expected, envelope.envelope
      end
    end

    context "revokable access" do
      test "copilot_revokable_access ff on" do
        enable_feature_flag(:copilot_revokable_access)
        enable_feature_flag(:copilot_respect_revokable_access)
        seat_assignment = create(:copilot_seat_assignment, :user, access_revoked_at: Time.now)
        user = seat_assignment.assignable
        copilot_user = Copilot::User.new(user)

        freeze_time do
          Copilot::User.any_instance.stubs(:can_signup_for_limited?).returns(true)
          auth = Copilot::Authorizer.new(copilot_user)
          refute auth.access_allowed?
          envelope = Copilot::Envelope.new(auth, Hash.new)
          expected = {
            message: "Resource not accessible by integration",
            error_details: {
              url: Copilot::Envelope::SETTINGS_PAGE,
              message: "Your Copilot access has been revoked by the providing organization or enterprise. You are currently logged in as #{user.login}.",
              title: "Copilot Settings",
              notification_id: "access_revoked",
            },
            can_signup_for_limited: true,
          }
          assert_equal expected, envelope.envelope
        end
      end

      test "copilot_revokable_access ff off" do
        disable_feature_flag(:copilot_revokable_access)
        seat_assignment = create(:copilot_seat_assignment, :user, access_revoked_at: Time.now)
        user = seat_assignment.assignable
        copilot_user = Copilot::User.new(user)

        freeze_time do
          auth = Copilot::Authorizer.new(copilot_user)
          envelope = Copilot::Envelope.new(auth, Hash.new)

          assert auth.access_allowed?
          refute envelope.envelope[:error_details]
        end
      end
    end

    test "revoked_coupon" do
      Copilot::User.any_instance.stubs(:public_code_suggestions_configured?).returns(true)
      Copilot::User.any_instance.stubs(:snippy_setting).returns("enabled")
      free_user = create(
        :copilot_free_user,
        :educational_redeemed,
        user: create(:credit_card_user),
        subscribed: true,
      )
      user = free_user.user
      user.expire_active_coupon
      user.reload
      free_user.destroy

      code = "revoked"
      coupon = Coupon.find_by(code: code) || create(:coupon, code: code)
      coupon.update(limit: 9999)
      user.redeem_coupon(coupon)

      copilot_user = Copilot::User.new(user)

      freeze_time do
        auth = Copilot::Authorizer.new(copilot_user)
        refute auth.access_allowed?
        envelope = Copilot::Envelope.new(auth, Hash.new)

        expected = {
          message: "Resource not accessible by integration",
          error_details: {
            url: Copilot::Envelope::SIGNUP_PAGE,
            message: "No access to GitHub Copilot found. You are currently logged in as #{copilot_user.user_object.login}.",
            title: "Sign up for GitHub Copilot",
            notification_id: "revoked_coupon"
          },
          can_signup_for_limited: false,
        }
        assert_equal expected, envelope.envelope
      end
    end
  end

  context "chat for all cfi ff" do
    test "generates a complete envelope with chat for free education" do
      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        copilot_user.allow_public_code_suggestions!
        expiry = 1643080461
        sku = "free_educational"

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)
        Copilot::Authorizer.any_instance.stubs(:access_type_sku).returns(sku)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal auth.access_type_sku, sku
        assert_equal copilot_user.user_object.analytics_tracking_id, "fake"
        assert_equal "dotcom", envelope.stamp

        known_token = "tid=fake;exp=1643080461;sku=free_educational;st=dotcom;chat=1;nes=0;editor_preview_features=0;rt=1;8kp=1:6cff1084421ed571e6ea8a4cd6daeafaef6c8b5163461aca51a20ceac21ddabc"

        assert_equal known_token, envelope.generate_v2_token

        expected = {
          annotations_enabled: false,
          chat_enabled: true,
          chat_jetbrains_enabled: true,
          code_quote_enabled: true,
          code_review_enabled: false,
          codesearch: true,
          copilotignore_enabled: false,
          endpoints: Copilot::SKUIsolation.new(copilot_user, nil).endpoints,
          expires_at: expiry,
          individual: true,
          nes_enabled: false,
          prompt_8k: true,
          public_suggestions: "disabled",
          refresh_in: 25.minutes.to_i,
          sku: sku,
          snippy_load_test_enabled: false,
          telemetry: "enabled",
          token: known_token,
          tracking_id: copilot_user.user_object.analytics_tracking_id,
          vsc_electron_fetcher_v2: false,
          xcode_chat: false,
          xcode: false,
          limited_user_quotas: nil,
          limited_user_reset_date: nil,
        }
        assert_equal expected, envelope.envelope
      end
    end
  end

  context "SKU isolation endpoints" do
    test "without the feature flags" do
      GitHub.stubs(:copilot_api_override_url).returns(nil) # Stub override to use default (production) URLs

      freeze_time do
        create :copilot_free_user,
          user: @user,
          subscribed: true,
          free_user_type: "Educational"

        copilot_user = Copilot::User.new(@user)
        copilot_user.allow_public_code_suggestions!

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert auth.access_allowed?

        expected = {
          "api" => "https://api.githubcopilot.com",
          "origin-tracker" => "https://origin-tracker.githubusercontent.com",
          "proxy" => "https://copilot-proxy.githubusercontent.com",
          "telemetry" => "https://copilot-telemetry-service.githubusercontent.com",
        }
        assert_equal expected, envelope.envelope[:endpoints],
          "includes the legacy endpoints in the envelope"

        token_parts = envelope.envelope[:token].split(";").first.split(":")
        proxy_ep = token_parts.find { _1.start_with?("proxy-ep=") }
        assert_nil proxy_ep,
          "does not include the proxy-ep parameter in the token"
      end
    end

    test "dotcom individual" do
      GitHub.stubs(:copilot_api_override_url).returns(nil) # Stub override to use default (production) URLs

      freeze_time do
        create(:copilot_free_user, user: @user, subscribed: true, free_user_type: "Educational")
        copilot_user = Copilot::User.new(@user)
        copilot_user.allow_public_code_suggestions!

        enable_feature_flag(:copilot_sku_isolation_discovery, @user)
        enable_feature_flag(:copilot_sku_isolation_enforce_proxy, @user)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal Copilot::SKUIsolation::INDIVIDUAL,
          envelope.sku_isolation.plan

        expected = {
          "api" => "https://api.individual.githubcopilot.com",
          "origin-tracker" => "https://origin-tracker.individual.githubcopilot.com",
          "proxy" => "https://proxy.individual.githubcopilot.com",
          "telemetry" => "https://telemetry.individual.githubcopilot.com",
        }
        assert_equal expected, envelope.envelope[:endpoints],
          "includes the SKU Isolation endpoints in the envelope"

        token_parts = envelope.envelope[:token].split(":").first.split(";")
        proxy_ep = token_parts.find { _1.start_with?("proxy-ep=") }
        assert_equal "proxy-ep=proxy.individual.githubcopilot.com", proxy_ep
      end
    end

    test "dotcom business" do
      GitHub.stubs(:copilot_api_override_url).returns(nil) # Stub override to use default (production) URLs

      freeze_time do
        org = create(:copilot_for_business_enabled_organization)
        org.add_member(@user)
        create(:copilot_seat, organization: org, assigned_user: @user)

        copilot_user = Copilot::User.new(@user)
        copilot_user.allow_public_code_suggestions!

        enable_feature_flag(:copilot_sku_isolation_discovery, org)
        enable_feature_flag(:copilot_sku_isolation_enforce_proxy, org)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal Copilot::SKUIsolation::BUSINESS,
          envelope.sku_isolation.plan

        expected = {
          "api" => "https://api.business.githubcopilot.com",
          "origin-tracker" => "https://origin-tracker.business.githubcopilot.com",
          "proxy" => "https://proxy.business.githubcopilot.com",
          "telemetry" => "https://telemetry.business.githubcopilot.com",
        }
        assert_equal expected, envelope.envelope[:endpoints]

        token_parts = envelope.envelope[:token].split(":").first.split(";")
        proxy_ep = token_parts.find { _1.start_with?("proxy-ep=") }
        assert_equal "proxy-ep=proxy.business.githubcopilot.com", proxy_ep
      end
    end

    test "dotcom enterprise" do
      GitHub.stubs(:copilot_api_override_url).returns(nil) # Stub override to use default (production) URLs

      freeze_time do
        org = create(:copilot_feature_enabled_enterprise_organization)
        org.add_member(@user)
        create :copilot_seat,
          organization: org,
          assigned_user: @user,
          copilot_plan: "enterprise"

        copilot_user = Copilot::User.new(@user)
        copilot_user.allow_public_code_suggestions!

        enable_feature_flag(:copilot_sku_isolation_discovery, org.business)
        enable_feature_flag(:copilot_sku_isolation_enforce_proxy, org.business)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new)

        assert_equal Copilot::SKUIsolation::ENTERPRISE,
          envelope.sku_isolation.plan

        expected = {
          "api" => "https://api.enterprise.githubcopilot.com",
          "origin-tracker" => "https://origin-tracker.enterprise.githubcopilot.com",
          "proxy" => "https://proxy.enterprise.githubcopilot.com",
          "telemetry" => "https://telemetry.enterprise.githubcopilot.com",
        }
        assert_equal expected, envelope.envelope[:endpoints]

        token_parts = envelope.envelope[:token].split(":").first.split(";")
        proxy_ep = token_parts.find { _1.start_with?("proxy-ep=") }
        assert_equal "proxy-ep=proxy.enterprise.githubcopilot.com", proxy_ep
      end
    end

    test "proxima" do
      GitHub.stubs(:copilot_api_override_url).returns(nil) # Stub override to use default (production) URLs

      freeze_time do
        user = create(:emu, :owner)
        business = user.enterprise_managed_business
        org = create(:organization, business: business, admin: user)

        on_multi_tenant_enterprise tenant: business do
          enable_feature_flag(:copilot_sku_isolation_discovery, user)
          enable_feature_flag(:copilot_sku_isolation_enforce_proxy, user)

          create :copilot_seat,
            organization: org,
            assigned_user: user,
            copilot_plan: "enterprise"

          copilot_user = Copilot::User.new(user)
          copilot_user.allow_public_code_suggestions!

          auth = Copilot::Authorizer.new(copilot_user)
          envelope = Copilot::Envelope.new(auth, Hash.new)

          expected = {
            "api" => "https://copilot-api.#{business.slug}.ghe.com",
            "origin-tracker" => "https://origin-tracker.enterprise.githubcopilot.com",
            "proxy" => "https://proxy.enterprise.githubcopilot.com",
            "telemetry" => "https://copilot-telemetry-service.#{business.slug}.ghe.com",
          }
          assert_equal expected, envelope.envelope[:endpoints]

          token_parts = envelope.envelope[:token].split(":").first.split(";")
          proxy_ep = token_parts.find { _1.start_with?("proxy-ep=") }
          assert_equal "proxy-ep=proxy.enterprise.githubcopilot.com", proxy_ep
        end
      end
    end
  end

  def encode_token(message)
    OpenSSL::HMAC.hexdigest(Copilot::Envelope::HMAC_ALGORITHM, GitHub.copilot_cdn_hmac_key.to_s, message)
  end
end if GitHub.copilot_enabled?

class Copilot::EnvelopeExternalCAPTest < GitHub::TestCase
  skip_unless_all [:idp_cap_available?, :copilot_enabled?]

  include ConditionalAccess::FilterTestHelper

  fixtures do
    @owner = create :emu, :owner, provider_type: :oidc
    @business = @owner.enterprise_managed_business
    @org = create :organization, business: @business, admin: @owner
    @org2 = create :organization, business: @business, admin: @owner

    @org.add_member(@owner)
    @org2.add_member(@owner)

    create(:copilot_seat, organization: @org, assigned_user: @owner)
    create(:copilot_seat, organization: @org2, assigned_user: @owner)

    @orca_model = create(
      :orca_model,
      organization: @org,
      resource: "resource",
      deployment: "deployment",
      created_at: 1.day.ago,
    )

    @orca_model2 = create(
      :orca_model,
      organization: @org2,
      resource: "resource2",
      deployment: "deployment2",
    )

    @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
  end

  setup do
    @tenant_provider = ::OIDC::TenantProvider.new(@business)
    disable_feature_flag(:disable_oidc_cap_cache)
    @business.enable_idp_ip_allowlist_for_web(actor: @owner)
  end

  context "#custom_model_list" do
    test "returns models with authorizing cap filter" do
      enable_feature_flag(:copilot_custom_models_ip_cap_filter, @owner)
      enable_feature_flag(:copilot_use_external_conditional_access, @owner)

      freeze_time do
        copilot_user = Copilot::User.new(@owner)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        envelope = Copilot::Envelope.new(auth, Hash.new, cap_authorizing_filter)

        assert_equal [@orca_model.resource_deployment, @orca_model2.resource_deployment],
          envelope.custom_model_list,
          "all models are accessible based on cap filtering"
      end
    end

    test "returns empty with unauthorizing cap filter for just external_conditional_access_policy" do
      enable_feature_flag(:copilot_custom_models_ip_cap_filter, @owner)
      enable_feature_flag(:copilot_use_external_conditional_access, @owner)

      freeze_time do
        copilot_user = Copilot::User.new(@owner)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        # authorized for :ip_allowlist but not :external_conditional_access_policy
        envelope = Copilot::Envelope.new(auth, Hash.new, cap_unauthorizing_filter([@orca_model, @orca_model2], :external_conditional_access_policy))

        assert_empty envelope.custom_model_list, "custom models list is filtered to empty"
      end
    end

    test "returns models with unauthorizing cap filter for just external_conditional_access_policy and ff off" do
      enable_feature_flag(:copilot_custom_models_ip_cap_filter, @owner)
      disable_feature_flag(:copilot_use_external_conditional_access, @owner)

      freeze_time do
        copilot_user = Copilot::User.new(@owner)
        expiry = 1643080461

        Copilot::Envelope.any_instance.stubs(:token_expiration).returns(expiry)

        auth = Copilot::Authorizer.new(copilot_user)
        # authorized for :ip_allowlist but not :external_conditional_access_policy
        envelope = Copilot::Envelope.new(auth, Hash.new, cap_unauthorizing_filter([@orca_model, @orca_model2], :external_conditional_access_policy))

        # models are still returned because with copilot_use_external_conditional_access disabled
        # the :external_conditional_access_policy is not evaluated
        assert_equal [@orca_model.resource_deployment, @orca_model2.resource_deployment],
          envelope.custom_model_list,
          "all models are accessible based on cap filtering"
      end
    end
  end
end
