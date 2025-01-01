# typed: true
# frozen_string_literal: true

require "test_helper"

class ConfigurableTest < GitHub::TestCase
  include GitHub::QueryAssertionTestHelpers

  fixtures do
    @business = create(:business)
    @org   = create(:organization)
    @repo  = create(:repository, owner: @org)

    @business.add_organization(@org)
  end

  context "#configuration_owners" do
    test "returns the full inheritance chain of a Configurable" do
      assert_equal [GitHub, @business, @org], @repo.configuration_owners
      assert_equal [GitHub, @business], @org.configuration_owners
      assert_equal [GitHub], @business.configuration_owners
      assert_equal [], GitHub.configuration_owners
    end
  end

  context "#async_configuation_owners" do
    test "returns a promise resolving to the full inheritance chain of a Configurable" do
      assert_equal [GitHub, @business, @org], @repo.async_configuration_owners.sync
      assert_equal [GitHub, @business], @org.async_configuration_owners.sync
      assert_equal [GitHub], @business.async_configuration_owners.sync
      assert_equal [], GitHub.async_configuration_owners.sync
    end
  end

  context ".preload_configuration" do
    test "pre-populates entries for a collection of configurable models" do
      user = create(:user)

      repo1 = create(:repository, owner: @org)
      repo2 = create(:repository, owner: user)

      %w[repo_key org_shadowed org_forced business_shadowed business_forced].each do |key|
        @repo.config.set(key, "repo_value_0", user)
      end

      %w[repo_key org_shadowed org_forced business_shadowed business_forced].each do |key|
        repo1.config.set(key, "repo_value_1", user)
      end

      %w[repo_key org_shadowed org_forced business_shadowed business_forced].each do |key|
        repo2.config.set(key, "repo_value_2", user)
      end

      %w[org_key org_shadowed].each { |key| @org.config.set(key, "org_value", user) }
      @org.config.set!("org_forced", "org_value", user)

      %w[business_key business_shadowed].each { |key| @business.config.set(key, "business_value", user) }
      @business.config.set!("business_forced", "business_value", user)

      [@repo, repo1, repo2, @org, @business].each { |configurable| configurable.reset_config }

      # Queries:
      # * Loading owner chains: 1 org + 1 user + 1 business = 3
      # * Loading all configuration entries = 1
      # Total: 4
      assert_query_counts(4, exclude_configuration_queries: false) do
        Configurable.preload_configuration([@repo, repo1, repo2])
      end

      GitHub::MysqlInstrumenter.reset_stats
      assert_query_counts(0, exclude_configuration_queries: false) do
        %w[repo_key org_shadowed business_shadowed].each do |repo_key|
          assert_equal "repo_value_0", @repo.config.get(repo_key)
          assert_equal "repo_value_1", repo1.config.get(repo_key)
          assert_equal "repo_value_2", repo2.config.get(repo_key)
        end

        assert_equal "org_value", @repo.config.get("org_forced")
        assert_equal "org_value", repo1.config.get("org_forced")
        assert_equal "repo_value_2", repo2.config.get("org_forced")

        assert_equal "business_value", @repo.config.get("business_forced")
        assert_equal "business_value", repo1.config.get("business_forced")
        if GitHub.single_business_environment?
          assert_equal "business_value", repo2.config.get("business_forced")
        else
          assert_equal "repo_value_2", repo2.config.get("business_forced")
        end
      end
    end

    test "disregards models that already have a Configuration loaded" do
      other = create(:repository)

      # Preload owner relationships to isolate config-fetching queries.
      [@repo, other].each(&:configuration_owners)

      assert_query_counts(1, exclude_configuration_queries: false) { Configurable.preload_configuration([@repo]) }

      # Lazily initialize the Configuration, but not its Entries
      other.config
      GitHub::MysqlInstrumenter.reset_stats
      assert_query_counts(1, exclude_configuration_queries: false) { Configurable.preload_configuration([@repo, other]) }

      GitHub::MysqlInstrumenter.reset_stats
      assert_query_counts(0, exclude_configuration_queries: false) { Configurable.preload_configuration([@repo, other]) }
    end
  end
end
