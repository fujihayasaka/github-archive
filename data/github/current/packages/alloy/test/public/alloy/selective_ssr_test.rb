# typed: strict
# frozen_string_literal: true

require "test_helper"

class AlloySelectiveSsrTest < GitHub::TestCase
  include Alloy::StubHelper

  context "#tier" do
    context "Tier 0" do
      test "override: true override takes precedence over other metadata" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: true,
          mobile: true,
          spammy: true,
          override: true,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_0, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end
    end

    context "Tier 1" do
      test "robot takes precedence as long it's not spammy or overriden" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: true,
          mobile: true,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_1, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end

      test "logged out takes precedence as long it's not spammy or overriden" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: false,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_1, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end

      test "highly cacheable content hint takes precedence as long it's not spammy or overriden" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new(highly_cacheable: true))
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_1, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end

      test "no js experience content hint takes precedence as long it's not spammy or overriden" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new(no_js_experience: true))
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_1, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end
    end

    context "Tier 2" do
      test "User logged in and mobile device" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_2, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end

      test "User logged in and tablet" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: ipad_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_2, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end

      test "User logged in and not a major browser" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: opera_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_2, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end

      test "User logged in and not a major OS" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_2, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end

      test "User logged in and sm CPU bucket" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: sm_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_2, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end

      test "User logged in and md CPU bucket" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: true,
          spammy: false,
          cpu_bucket: md_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_2, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end
    end

    context "Tier 3" do
      test "User is logged in without any modifiers" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: true,
          robot: false,
          mobile: false,
          spammy: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_3, selective_ssr.tier
        assert_equal true, selective_ssr.ssr_enabled?
      end
    end

    context "Tier 4" do
      test "Spammy users take precedence as long it's not overriden with override: true" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: false,
          robot: true,
          mobile: true,
          spammy: true,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_4, selective_ssr.tier
        assert_equal false, selective_ssr.ssr_enabled?
      end

      test "override: false override takes precedence over other metadata" do
        metadata = Alloy::SelectiveSsr::Metadata.new(
          logged_in: false,
          robot: true,
          mobile: true,
          spammy: false,
          override: false,
          cpu_bucket: lg_cpu_bucket,
          user_agent: chrome_os_user_agent
        )

        selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
        assert_equal Alloy::SelectiveSsr::Tiers::TIER_4, selective_ssr.tier
        assert_equal false, selective_ssr.ssr_enabled?
      end
    end
  end

  context "#determine_cpu_bucket" do
    test "returns unknown if cookie is blank" do
      request = ActionDispatch::Request.new({})
      assert_equal Alloy::SelectiveSsr.determine_cpu_bucket(request), Alloy::SelectiveSsr::DEFAULT_CPU_BUCKET

      request.cookies["cpu_bucket"] = ""
      assert_equal Alloy::SelectiveSsr.determine_cpu_bucket(request), Alloy::SelectiveSsr::DEFAULT_CPU_BUCKET
    end

    test "returns unknown if cookie is invalid" do
      request = ActionDispatch::Request.new({})
      request.cookies["cpu_bucket"] = "invalid"

      assert_equal Alloy::SelectiveSsr.determine_cpu_bucket(request), Alloy::SelectiveSsr::DEFAULT_CPU_BUCKET
    end

    test "returns value from cookie if it's valid" do
      request = ActionDispatch::Request.new({})
      request.cookies["cpu_bucket"] = "sm"

      assert_equal Alloy::SelectiveSsr.determine_cpu_bucket(request), "sm"
    end
  end

  context "when not using manifest as source of truth" do
    test "returns false if ssr_override is not used and app is not in manifest" do
      with_stubbed_manifest do
        assert_equal Alloy::SelectiveSsr.determine_selective_ssr_override(nil, "test"), false
      end
    end

    test "returns ssr_override whenever present and app is in manifest" do
      with_stubbed_manifest do
        assert_equal Alloy::SelectiveSsr.determine_selective_ssr_override(false, "react-sandbox"), false
        assert_equal Alloy::SelectiveSsr.determine_selective_ssr_override(false, "react-sandbox"), false
        assert_equal Alloy::SelectiveSsr.determine_selective_ssr_override(true, "react-sandbox"), true
        assert_equal Alloy::SelectiveSsr.determine_selective_ssr_override(true, "react-sandbox"), true
      end
    end
  end

  context "useragent parsing" do
    test "Truncates instead of erroring when user_agent length exceeds limit" do
      metadata = Alloy::SelectiveSsr::Metadata.new(
        logged_in: false,
        robot: true,
        mobile: true,
        spammy: true,
        cpu_bucket: lg_cpu_bucket,
        user_agent: long_user_agent
      )

      selective_ssr = Alloy::SelectiveSsr.new(metadata: metadata, hints: Alloy::SelectiveSsr::Hints.new)
      assert_equal Alloy::SelectiveSsr::Tiers::TIER_4, selective_ssr.tier
      assert_equal false, selective_ssr.ssr_enabled?
    end
  end

  sig { returns(String) }
  def chrome_user_agent
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
  end

  sig { returns(String) }
  def ipad_user_agent
    "Mozilla/5.0(iPad; U; CPU iPhone OS 3_2 like Mac OS X; en-us) AppleWebKit/531.21.10 (KHTML, like Gecko) Version/4.0.4 Mobile/7B314 Safari/531.21.10"
  end

  sig { returns(String) }
  def opera_user_agent
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36 OPR/114.0.0.0"
  end

  sig { returns(String) }
  def chrome_os_user_agent
    "Mozilla/5.0 (X11; CrOS x86_64 15917.71.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.6533.132 Safari/537.36"
  end

  sig { returns(String) }
  def long_user_agent
    "Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 5.1; Trident/4.0; YPC 3.2.0; SearchSystem6829992239; SearchSystem9616306563; SearchSystem6017393645; SearchSystem5219240075; SearchSystem2768350104; SearchSystem6919669052; SearchSystem1986739074; SearchSystem1555480186; SearchSystem3376893470; SearchSystem9530642569; SearchSystem4877790286; SearchSystem8104932799; SearchSystem2313134663; SearchSystem1545325372; SearchSystem7742471461; SearchSystem9092363703; SearchSystem6992236221; SearchSystem3507700306; SearchSystem1129983453; SearchSystem1077927937; SearchSystem2297142691; SearchSystem7813572891; SearchSystem5668754497; SearchSystem6220295595; SearchSystem4157940963; SearchSystem7656671655; SearchSystem2865656762; SearchSystem6520604676; SearchSystem4960161466; .NET CLR 1.1.4322; .NET CLR 2.0.50727; Hotbar 10.2.232.0; SearchSystem9616306563; SearchSystem6017393645; SearchSystem5219240075; SearchSystem2768350104; SearchSystem6919669052; SearchSystem1986739074; SearchSystem1555480186; SearchSystem3376893470; SearchSystem9530642569; SearchSystem4877790286; SearchSystem8104932799; SearchSystem2313134663; SearchSystem1545325372; SearchSystem7742471461; SearchSystem9092363703; SearchSystem6992236221; SearchSystem3507700306; SearchSystem1129983453; SearchSystem1077927937; SearchSystem2297142691; SearchSystem7813572891; SearchSystem5668754497; SearchSystem6220295595; SearchSystem4157940963; SearchSystem7656671655; SearchSystem2865656762; SearchSystem6520604676; SearchSystem4960161466;  SearchSystem8104932799; SearchSystem2313134663; SearchSystem1545325372; SearchSystem7742471461; SearchSystem9092363703; SearchSystem6992236221; SearchSystem3507700306; SearchSystem1129983453; SearchSystem1077927937; SearchSystem2297142691; SearchSystem7813572891; SearchSystem5668754497; SearchSystem6220295595; SearchSystem4157940963; SearchSystem7656671655; SearchSystem2865656762; SearchSystem6520604676; SearchSystem4960161466; .NET CLR 1.1.4322; .NET CLR 2.0.50727; Hotbar 10.2.232.0; SearchSystem9616306563; SearchSystem6017393645; SearchSystem5219240075; SearchSystem2768350104; SearchSystem6919669052; SearchSystem1986739074; SearchSystem1555480186; SearchSystem3376893470; SearchSystem9530642569; SearchSystem4877790286; SearchSystem8104932799; SearchSystem2313134663; SearchSystem1545325372; SearchSystem7742471461; SearchSystem9092363703; SearchSystem6992236221; SearchSystem3507700306; SearchSystem1129983453; SearchSystem1077927937; SearchSystem2297142691; SearchSystem7813572891; SearchSystem5668754497; SearchSystem6220295595; SearchSystem4157940963; SearchSystem7656671655; SearchSystem2865656762; SearchSystem6520604676; SearchSystem4960161466;  SearchSystem8104932799; SearchSystem2313134663; SearchSystem1545325372; SearchSystem7742471461; SearchSystem9092363703; SearchSystem6992236221; SearchSystem3507700306; SearchSystem1129983453; SearchSystem1077927937; SearchSystem2297142691; SearchSystem7813572891; SearchSystem5668754497; SearchSystem6220295595; SearchSystem4157940963; SearchSystem7656671655; SearchSystem2865656762; SearchSystem6520604676; SearchSystem4960161466; .NET CLR 1.1.4322; .NET CLR 2.0.50727; Hotbar 10.2.232.0; SearchSystem9616306563; SearchSystem6017393645; SearchSystem5219240075; SearchSystem2768350104; SearchSystem6919669052; SearchSystem1986739074; SearchSystem1555480186; SearchSystem3376893470; SearchSystem9530642569; SearchSystem4877790286; SearchSystem8104932799; SearchSystem2313134663; SearchSystem1545325372; SearchSystem7742471461; SearchSystem9092363703; SearchSystem6992236221; SearchSystem3507700306; SearchSystem1129983453; SearchSystem1077927937; SearchSystem2297142691; SearchSystem7813572891; SearchSystem5668754497; SearchSystem6220295595; SearchSystem4157940963; SearchSystem7656671655; SearchSystem2865656762; SearchSystem6520604676; SearchSystem4960161466; .NET CLR 3.0.4506.2152; .NET CLR 3.5.30729)"
  end

  sig { returns(String) }
  def sm_cpu_bucket
    "sm"
  end

  sig { returns(String) }
  def md_cpu_bucket
    "md"
  end

  sig { returns(String) }
  def lg_cpu_bucket
    "lg"
  end
end
