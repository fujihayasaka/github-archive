# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryLimitTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @owner = create(:user)
    @owner_repos = create_list(:repository, 15, owner: @owner)
    @owner_deleted_repo = create(:repository, :soft_deleted, owner: @owner)
    @owner_failed_repo = create(:repository, :failed_creation, owner: @owner)

    @repo_count = 15
  end

  def limiter
    RepositoryLimit.new(@owner)
  end

  test "#enabled?" do
    assert_equal TestEnv.test_all_features? && !GitHub.single_tenant_enterprise?, limiter.enabled?
  end

  context "#override" do
    test "override only hard limit" do
      assert limiter.soft_limit, 50_000
      assert limiter.hard_limit, 100_000

      assert_raises(ArgumentError) do
        limiter.override(hard: 0)
      end
      limiter.override(hard: 150_000)
      assert_raises(ArgumentError) do
        limiter.override(hard: 2_000_001)
      end

      assert limiter.overridden?
      assert limiter.soft_limit, 50_000
      assert limiter.hard_limit, 150_000
    end

    test "override only soft limit" do
      assert limiter.soft_limit, 50_000
      assert limiter.hard_limit, 100_000

      assert_raises(ArgumentError) do
        limiter.override(soft: 0)
      end
      limiter.override(soft: 10_000)
      assert_raises(ArgumentError) do
        limiter.override(soft: 2_000_001)
      end

      assert limiter.overridden?
      assert limiter.soft_limit, 10_000
      assert limiter.hard_limit, 100_000
    end

    test "override both limits" do
      assert_raises(ArgumentError) do
        limiter.override(soft: 5, hard: 4)
      end

      limiter.override(soft: 5, hard: 10)

      assert limiter.overridden?
      assert limiter.soft_limit, 5
      assert limiter.hard_limit, 10
    end
  end

  test "#soft_limit" do
    assert_equal 50_000, limiter.soft_limit
  end

  test "#soft_limited?" do
    stub(soft: @repo_count + 1) { refute limiter.soft_limited? }
    if GitHub.flipper[:repos_limits].enabled?
      stub(soft: @repo_count) { assert limiter.soft_limited? }
      stub(soft: @repo_count - 1) { assert limiter.soft_limited? }
    else
      stub(soft: @repo_count) { refute limiter.soft_limited? }
      stub(soft: @repo_count - 1) { refute limiter.soft_limited? }
    end
  end

  test "#soft_limited? when over hard limit" do
    limiter.override(soft:  @repo_count - 2, hard: @repo_count - 1)

    if GitHub.flipper[:repos_limits].enabled?
      refute limiter.soft_limited?
      assert limiter.hard_limited?
    else
      refute limiter.soft_limited?
      refute limiter.hard_limited?
    end
  end

  test "#at_soft_limit?" do
    stub(soft: @repo_count + 1) { refute limiter.at_soft_limit? }
    if GitHub.flipper[:repos_limits].enabled?
      stub(soft: @repo_count) { assert limiter.at_soft_limit? }
    else
      stub(soft: @repo_count) { refute limiter.at_soft_limit? }
    end
    stub(soft: @repo_count - 1) { refute limiter.at_soft_limit? }
  end

  test "#send_soft_limit_email?", skip_enterprise: true do
    enable_feature_flag(:repos_limits)

    RepositoryLimit.any_instance.stubs(:count).returns(49_000)
    refute limiter.send_soft_limit_email?
    RepositoryLimit.any_instance.stubs(:count).returns(50_000)
    assert limiter.send_soft_limit_email?
    RepositoryLimit.any_instance.stubs(:count).returns(50_001)
    refute limiter.send_soft_limit_email?
    RepositoryLimit.any_instance.stubs(:count).returns(55_000)
    assert limiter.send_soft_limit_email?
    RepositoryLimit.any_instance.stubs(:count).returns(100_000)
    refute limiter.send_soft_limit_email?
    RepositoryLimit.any_instance.stubs(:count).returns(100_001)
    refute limiter.send_soft_limit_email?
    RepositoryLimit.any_instance.stubs(:count).returns(105_000)
    refute limiter.send_soft_limit_email?
  end

  test "#hard_limit" do
    assert_equal 100_000, limiter.hard_limit
    limiter.override(hard: 150_000)
    assert_equal 150_000, limiter.hard_limit
  end

  context "#hard_limited?" do
    test "default limit" do
      stub(hard: @repo_count + 1) { refute limiter.hard_limited? }
      if GitHub.flipper[:repos_limits].enabled?
        stub(hard: @repo_count) { assert limiter.hard_limited? }
        stub(hard: @repo_count - 1) { assert limiter.hard_limited? }
      else
        stub(hard: @repo_count) { refute limiter.hard_limited? }
        stub(hard: @repo_count - 1) { refute limiter.hard_limited? }
      end
    end

    test "override limit" do
      limiter.override(soft: @repo_count - 5, hard: @repo_count + 1)
      refute limiter.hard_limited?
      if GitHub.flipper[:repos_limits].enabled?
        limiter.override(hard: @repo_count)
        assert limiter.hard_limited?
        limiter.override(hard: @repo_count - 1)
        assert limiter.hard_limited?
      else
        limiter.override(hard: @repo_count)
        refute limiter.hard_limited?
        limiter.override(hard: @repo_count - 1)
        refute limiter.hard_limited?
      end
    end
  end

  context "#at_hard_limit?" do
    test "default limits" do
      stub(hard: @repo_count + 1) { refute limiter.at_hard_limit? }
      if GitHub.flipper[:repos_limits].enabled?
        stub(hard: @repo_count) { assert limiter.at_hard_limit? }
      else
        stub(hard: @repo_count) { refute limiter.at_hard_limit? }
      end
      stub(hard: @repo_count - 1) { refute limiter.at_hard_limit? }
    end

    test "override limits" do
      limiter.override(soft: @repo_count - 5, hard: @repo_count + 1)
      refute limiter.at_hard_limit?
      if GitHub.flipper[:repos_limits].enabled?
        limiter.override(hard: @repo_count)
        assert limiter.at_hard_limit?
      else
        limiter.override(hard: @repo_count)
        refute limiter.at_hard_limit?
      end
      limiter.override(hard: @repo_count - 1)
      refute limiter.at_hard_limit?
    end
  end

  context "audit log" do
    test "instruments repository limit warning for org", skip_enterprise: true do
      enable_feature_flag(:repos_limits)
      events = subscribe "repository_limit.warning"

      owner_org = create(:organization)
      owner_org.add_member(@owner)
      owner_repos = create_list(:repository, 15, owner: owner_org, created_by_user_id: @owner.id)

      RepositoryLimit.new(owner_org).override(soft: 10, hard: 17)

      create(:repository, :full_creation, {
        owner: owner_org,
        created_by_user_id: @owner.id,
        gitignore_template: "Python",
        license_template: "mit",
        auto_init: true,
        template: false,
      })

      org_limiter = RepositoryLimit.new(owner_org)
      expected_payload = {
        limit: org_limiter.hard_limit,
        count: org_limiter.count,
        org: "#{owner_org}",
        org_id: owner_org.id,
        owner: "#{owner_org}",
        owner_id: owner_org.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "repository_limit.warning", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments approaching repository limit", skip_enterprise: true do
      enable_feature_flag(:repos_limits)
      events = subscribe "repository_limit.warning"
      limiter.override(soft: @repo_count - 5, hard: @repo_count + 2)

      create(:repository, :full_creation, {
        owner: @owner,
        created_by_user_id: @owner.id,
        gitignore_template: "Python",
        license_template: "mit",
        auto_init: true,
        template: false,
      })

      expected_payload = {
        limit: limiter.hard_limit,
        count: limiter.count,
        owner: "#{@owner}",
        owner_id: @owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "repository_limit.warning", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments repository limit reached", skip_enterprise: true do
      enable_feature_flag(:repos_limits)
      events = subscribe "repository_limit.reached"
      limiter.override(soft: @repo_count - 5, hard: @repo_count + 1)

      create(:repository, :full_creation, {
        owner: @owner,
        created_by_user_id: @owner.id,
        gitignore_template: "Python",
        license_template: "mit",
        auto_init: true,
        template: false,
      })

      expected_payload = {
        limit: limiter.hard_limit,
        count: limiter.count,
        owner: "#{@owner}",
        owner_id: @owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "repository_limit.reached", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments the repo limit override creation" do
      enable_feature_flag(:repos_limits)
      events = subscribe "repository_limit.create_override"
      limiter.override(soft: @repo_count - 5, hard: @repo_count + 1)

      expected_payload = {
        soft_limit: @repo_count - 5,
        hard_limit: @repo_count + 1,
        owner: "#{@owner}",
        owner_id: @owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "repository_limit.create_override", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments the repo limit override update" do
      enable_feature_flag(:repos_limits)
      events = subscribe "repository_limit.update_override"
      limiter.override(soft: @repo_count - 5, hard: @repo_count + 1)
      limiter.override(soft: @repo_count - 3, hard: @repo_count + 3)

      expected_payload = {
        soft_limit: @repo_count - 3,
        hard_limit: @repo_count + 3,
        owner: "#{@owner}",
        owner_id: @owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "repository_limit.update_override", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments the repo limit override reset" do
      enable_feature_flag(:repos_limits)
      events = subscribe "repository_limit.reset_override"
      limiter.reset_override

      expected_payload = {
        soft_limit: RepositoryLimit::SOFT_LIMIT,
        hard_limit: RepositoryLimit::HARD_LIMIT,
        owner: "#{@owner}",
        owner_id: @owner.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "repository_limit.reset_override", event.name
      assert_equal expected_payload, event.payload
    end
  end

  def stub(override, &block)
    raise ArgumentError, "You must provide a single override" if override.keys.length != 1
    raise ArgumentError, "Override key must be ':soft' or ':hard'" if (override.keys - [:soft, :hard]).any?

    const = override.keys.first == :soft ? :SOFT_LIMIT : :HARD_LIMIT
    stub_const(RepositoryLimit, const, override.values.first) do
      yield
    end
  end
end
