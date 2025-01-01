# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class SiteScopedIntegrationInstallation::CacheTest < GitHub::TestCase
  fixtures do
    @namespace = "generate_site_scoped_token_test"

    @target = create(:user)
    @repository = create(:repository, :minimal, owner: @target)

    disable_feature_flag(:disabled_global_apps)
    @integration = create_unlimited_global_integration(
      permissions: { "metadata" => :read, "contents" => :read },
    )
    @site_scoped_installation = make_site_scoped_integration_installation(
      integration: @integration, target: @target, repositories: [@repository],
    )
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_cache
  end

  teardown_once do
    disable_cache_storage
  end

  test ".cache_key_prefix" do
    expected = "github:api:site_scoped_installation"
    assert_equal expected, SiteScopedIntegrationInstallation::Cache.cache_key_prefix
  end

  context "#get" do
    test "returns nil if nothing was found in the cache" do
      refute GitHub.cache.exist?(subject.cache_key)
      assert_nil subject.get
    end

    test "returns nil if the cached ID was found, but the record is missing" do
      assert_predicate @site_scoped_installation, :persisted?

      GitHub.cache.set(subject.cache_key, @site_scoped_installation.id, 1.day)
      refute_nil GitHub.cache.exist?(subject.cache_key)

      assert @site_scoped_installation.destroy
      assert_nil subject.get
    end

    test "returns a SiteScopedIntegrationInstallation record" do
      assert_predicate @site_scoped_installation, :persisted?

      GitHub.cache.set(subject.cache_key, @site_scoped_installation.id, 1.day)
      refute_nil GitHub.cache.exist?(subject.cache_key)

      cached_installation = subject.get
      assert_equal @site_scoped_installation, cached_installation
    end
  end

  context "#exist?" do
    test "returns false if the cached_id couldn't be found" do
      refute GitHub.cache.exist?(subject.cache_key)
      refute subject.exist?

      expected_stats_key = "api.integrations.access_tokens.create.#{@namespace}.cache"
      assert_equal 1, GitHub.dogstats.increments(expected_stats_key, tags: ["result:miss"]).count
    end

    test "returns true if the cached ID has a matching record" do
      assert_predicate @site_scoped_installation, :persisted?

      GitHub.cache.set(subject.cache_key, @site_scoped_installation.id, 1.day)

      assert_predicate subject, :exist?
    end

    test "returns false if the cached ID doesn't have a matching record" do
      assert_predicate @site_scoped_installation, :persisted?

      GitHub.cache.set(subject.cache_key, @site_scoped_installation.id, 1.day)
      assert @site_scoped_installation.destroy

      refute_predicate subject, :exist?

      expected_stats_key = "api.integrations.access_tokens.create.#{@namespace}.cache.record_missing"
      assert_equal 1, GitHub.dogstats.increments(expected_stats_key).count
    end
  end

  context "#set" do
    test "does not write to the cache if the result was unsuccessful" do
      failed_result = SiteScopedIntegrationInstallation::Creator::Result.new(:failed, error: "message")
      GitHub.cache.expects(:set).never
      subject.set(failed_result)
      refute GitHub.cache.exist?(subject.cache_key)
    end

    test "does not write to the cache if the previous #exist? was successful" do
      result1 = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @target, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case
      )
      assert_predicate result1, :success?

      subject.set(result1)

      result2 = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @target, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case
      )
      assert_predicate result2, :success?

      assert_predicate subject, :exist?

      expected_stats_key = "api.integrations.access_tokens.create.#{@namespace}.cache"
      assert_equal 1, GitHub.dogstats.increments(expected_stats_key, tags: ["result:hit"]).count

      subject.set(result2)

      cached_id = GitHub.cache.get(subject.cache_key)
      assert_equal result1.installation.id, cached_id
    end

    test "writes to the cache" do
      result = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @target, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case
      )
      assert_predicate result, :success?

      subject.set(result)

      cached_id = GitHub.cache.get(subject.cache_key)
      assert_equal result.installation.id, cached_id
    end
  end

  private

  def subject
    return @subject if defined?(@subject)
    @subject = SiteScopedIntegrationInstallation::Cache.new(
      @namespace, @integration, @target, [@repository.id], { "metadata" => :read },
    )
  end
end
