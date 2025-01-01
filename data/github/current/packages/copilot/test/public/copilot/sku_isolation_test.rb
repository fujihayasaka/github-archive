# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotSKUIsolationTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @copilot_user = Copilot::User.new(@user)
    @sku_isolation = Copilot::SKUIsolation.new(@copilot_user, nil)
  end

  [
    [:discovery_enabled?, :copilot_sku_isolation_discovery],
    [:enforce_api?, :copilot_sku_isolation_enforce_api],
    [:enforce_proxy?, :copilot_sku_isolation_enforce_proxy]
  ].each do |method_name, flipper_key|
    context "##{method_name}" do
      test "defaults to false" do
        GitHub.flipper[flipper_key].disable

        assert_equal false, @sku_isolation.send(method_name)
      end

      test "returns true if the feature flag is enabled for the user" do
        GitHub.flipper[flipper_key].enable(@copilot_user)

        assert_equal true, @sku_isolation.send(method_name)
      end

      test "returns true if the feature flag is enabled for a Copilot organization" do
        org = create(:copilot_for_business_enabled_organization)
        org.add_member(@user)
        create(:copilot_seat, organization: org, assigned_user: @user)

        GitHub.flipper[flipper_key].enable(org)

        assert_equal true, @sku_isolation.send(method_name)
      end

      test "returns true if the feature flag is enabled for a Copilot business" do
        org = create(:copilot_feature_enabled_enterprise_organization)
        org.add_member(@user)
        create :copilot_seat,
          organization: org,
          assigned_user: @user,
          copilot_plan: "enterprise"

        GitHub.flipper[flipper_key].enable(org.business)

        assert_equal true, @sku_isolation.send(method_name)
      end
    end
  end

  context "#plan" do
    Copilot::SKUIsolation::ALL_PLANS.each do |plan|
      test plan do
        @sku_isolation.stubs(:copilot_user_plan).returns(plan)

        assert_equal plan, @sku_isolation.plan
      end
    end

    test "returns business for standalone business" do
      @sku_isolation.stubs(:copilot_user_plan).returns("individual")
      @sku_isolation.stubs(:has_copilot_standalone_business?).returns(true)

      assert_equal Copilot::SKUIsolation::BUSINESS, @sku_isolation.plan
    end

    test "returns individual for unknown plans" do
      @sku_isolation.stubs(:copilot_user_plan).returns("unknown")

      assert_equal Copilot::SKUIsolation::INDIVIDUAL, @sku_isolation.plan
    end
  end

  context "#endpoints" do
    test "returns a hash of all service endpoints" do
      expected = {
        "api" => @sku_isolation.api.endpoint,
        "origin-tracker" => @sku_isolation.origin_tracker.endpoint,
        "proxy" => @sku_isolation.proxy.endpoint,
        "telemetry" => @sku_isolation.telemetry.endpoint,
      }

      assert_equal expected, @sku_isolation.endpoints
    end
  end

  [
    ["api", nil, nil, "api.githubcopilot.com"],
    ["api", "individual", nil, "api.individual.githubcopilot.com"],
    ["api", "business", nil, "api.business.githubcopilot.com"],
    ["api", "enterprise", nil, "api.enterprise.githubcopilot.com"],
    ["api", nil, "proxima-slug", "copilot-api.proxima-slug.ghe.com"],
    ["api", "individual", "proxima-slug", "copilot-api.proxima-slug.ghe.com"],
    ["api", "business", "proxima-slug", "copilot-api.proxima-slug.ghe.com"],
    ["api", "enterprise", "proxima-slug", "copilot-api.proxima-slug.ghe.com"],
    ["origin_tracker", nil, nil, "origin-tracker.githubusercontent.com"],
    ["origin_tracker", "individual", nil, "origin-tracker.individual.githubcopilot.com"],
    ["origin_tracker", "business", nil, "origin-tracker.business.githubcopilot.com"],
    ["origin_tracker", "enterprise", nil, "origin-tracker.enterprise.githubcopilot.com"],
    ["origin_tracker", nil, "proxima-slug", "origin-tracker.githubusercontent.com"],
    ["origin_tracker", "individual", "proxima-slug", "origin-tracker.individual.githubcopilot.com"],
    ["origin_tracker", "business", "proxima-slug", "origin-tracker.business.githubcopilot.com"],
    ["origin_tracker", "enterprise", "proxima-slug", "origin-tracker.enterprise.githubcopilot.com"],
    ["proxy", nil, nil, "copilot-proxy.githubusercontent.com"],
    ["proxy", "individual", nil, "proxy.individual.githubcopilot.com"],
    ["proxy", "business", nil, "proxy.business.githubcopilot.com"],
    ["proxy", "enterprise", nil, "proxy.enterprise.githubcopilot.com"],
    ["proxy", nil, "proxima-slug", "copilot-proxy.githubusercontent.com"],
    ["proxy", "individual", "proxima-slug", "proxy.individual.githubcopilot.com"],
    ["proxy", "business", "proxima-slug", "proxy.business.githubcopilot.com"],
    ["proxy", "enterprise", "proxima-slug", "proxy.enterprise.githubcopilot.com"],
    ["telemetry", nil, nil, "copilot-telemetry-service.githubusercontent.com"],
    ["telemetry", "individual", nil, "telemetry.individual.githubcopilot.com"],
    ["telemetry", "business", nil, "telemetry.business.githubcopilot.com"],
    ["telemetry", "enterprise", nil, "telemetry.enterprise.githubcopilot.com"],
    ["telemetry", nil, "proxima-slug", "copilot-telemetry-service.proxima-slug.ghe.com"],
    ["telemetry", "individual", "proxima-slug", "copilot-telemetry-service.proxima-slug.ghe.com"],
    ["telemetry", "business", "proxima-slug", "copilot-telemetry-service.proxima-slug.ghe.com"],
    ["telemetry", "enterprise", "proxima-slug", "copilot-telemetry-service.proxima-slug.ghe.com"],
  ].each do |service_method, plan, slug, expected_host|
    context "##{service_method}" do
      if plan
        name = "#{plan}"
      else
        name = "legacy"
      end

      if slug
        name += " with #{slug}"
      end

      test name do
        if plan
          GitHub.flipper[:copilot_sku_isolation_discovery].enable(@user)
        else
          GitHub.flipper[:copilot_sku_isolation_discovery].disable(@user)
        end

        if slug
          proxima_business = build(
            :business,
            :enterprise_managed_business,
            slug: slug,
          )
        end

        @sku_isolation.stubs(:plan).returns(plan)
        @sku_isolation.stubs(:current_tenant).returns(proxima_business)

        service = @sku_isolation.send(service_method)
        assert_equal expected_host, service.host
        assert_equal "https://#{expected_host}", service.endpoint
      end
    end
  end
end
