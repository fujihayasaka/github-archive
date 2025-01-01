# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class InstallationCacheBaseTest < GitHub::TestCase

  class DummyInstallationCache < InstallationCacheBase
    def self.cache_key_prefix
      "github:api:dummy_installation_cache"
    end

    def self.installation_class
      ScopedIntegrationInstallation
    end

    def parent_fragments
      []
    end
  end

  class DummyV2InstallationCache < DummyInstallationCache
    def self.cache_key_prefix
      "github:api:dummy_v2_installation_cache"
    end
  end

  fixtures do
    @namespace = "generate_dummy_token_test"
    @user = create(:user)
    @repository = create(:repository, :minimal, owner: @user)
    @parent = make_integration_installation(
      target: @user, permissions: { "metadata" => :read, "contents" => :read }
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

  test ".cache_key_prefix has to be implemented by subclass" do
    assert_raises NotImplementedError do
      InstallationCacheBase.cache_key_prefix
    end
  end

  test ".installation_class has to be implemented by subclass" do
    assert_raises NotImplementedError do
      InstallationCacheBase.installation_class
    end
  end

  test "#parent_fragments" do
    assert_raises NotImplementedError do
      InstallationCacheBase.new(
        @namespace, @parent, [@repository.id], { "metadata" => :read }
      ).parent_fragments
    end
  end

  context "#get" do
    test "returns nil if nothing was found in the cache" do
      refute GitHub.cache.exist?(subject.cache_key)
      assert_nil subject.get
    end

    test "cache keys are different for each cache store" do
      refute_equal subject.cache_key, subject_v2.cache_key
      assert_match "dummy_installation", subject.cache_key
      assert_match "dummy_v2_installation", subject_v2.cache_key
    end

    test "returns nil if the cached ID was found, but the record is missing" do
      result = ScopedIntegrationInstallation::Creator.perform(@parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      GitHub.cache.set(subject.cache_key, result.installation.id, 1.day)
      refute_nil GitHub.cache.exist?(subject.cache_key)

      result.installation.destroy
      assert_nil subject.get
    end

    test "returns a ScopedIntegrationInstallation record" do
      result = ScopedIntegrationInstallation::Creator.perform(@parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      GitHub.cache.set(subject.cache_key, result.installation.id, 1.day)
      refute_nil GitHub.cache.exist?(subject.cache_key)

      cached_installation = subject.get
      assert_equal result.installation, cached_installation

      # test it doesn't return the installation if using another cache
      v2_cached_installation = subject_v2.get
      assert_nil v2_cached_installation
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
      result = ScopedIntegrationInstallation::Creator.perform(@parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      GitHub.cache.set(subject.cache_key, result.installation.id, 1.day)

      assert_predicate subject, :exist?
      # test it doesn't exist in another cache
      refute_predicate subject_v2, :exist?
    end

    test "returns false if the cached ID doesn't have a matching record" do
      result = ScopedIntegrationInstallation::Creator.perform(@parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      GitHub.cache.set(subject.cache_key, result.installation.id, 1.day)
      result.installation.destroy

      refute_predicate subject, :exist?

      expected_stats_key = "api.integrations.access_tokens.create.#{@namespace}.cache.record_missing"
      assert_equal 1, GitHub.dogstats.increments(expected_stats_key).count
    end
  end

  context "#set" do
    test "does not write to the cache if the result was unsuccessful" do
      result = ScopedIntegrationInstallation::Creator.perform(@parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      failed_result = ScopedIntegrationInstallation::Result.new(:failed, installation: result.installation, error: "message")

      subject.set(failed_result)
      refute GitHub.cache.exist?(subject.cache_key)
    end

    test "does not write to the cache if the previous #exist? was successful" do
      result1 = ScopedIntegrationInstallation::Creator.perform(@parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result1, :success?

      subject.set(result1)

      result2 = ScopedIntegrationInstallation::Creator.perform(@parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result2, :success?

      assert_predicate subject, :exist?

      expected_stats_key = "api.integrations.access_tokens.create.#{@namespace}.cache"
      assert_equal 1, GitHub.dogstats.increments(expected_stats_key, tags: ["result:hit"]).count

      subject.set(result2)

      cached_id = GitHub.cache.get(subject.cache_key)
      assert_equal result1.installation.id, cached_id

      # test it doesn't touch other cache store
      refute GitHub.cache.exist?(subject_v2.cache_key)
    end

    test "writes to the cache" do
      subject = DummyInstallationCache.new(@namespace, @parent, [@repository.id], { "metadata" => :read })

      result = ScopedIntegrationInstallation::Creator.perform(@parent, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case)
      assert_predicate result, :success?

      subject.set(result)

      cached_id = GitHub.cache.get(subject.cache_key)
      assert_equal result.installation.id, cached_id
    end
  end

  private

  def subject
    return @subject if defined?(@subject)

    @subject = DummyInstallationCache.new(
      @namespace, @parent, [@repository.id], { "metadata" => :read }
    )
  end

  def subject_v2
    return @subject_v2 if defined?(@subject_v2)

    @subject_v2 = DummyV2InstallationCache.new(
      @namespace, @parent, [@repository.id], { "metadata" => :read }
    )
  end
end
