# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotContentExclusionsRulesResolver < GitHub::TestCase
  include CopilotTestHelper

  fixtures do
    @org = create(:copilot_for_business_enabled_organization)

    @org_document = <<~YAML
      "*": ["/wildcard-path/*"]
      https://gitlab.com/team/repo: ["/gitlab/*"]
      smile: ["/smile*"]
      git@gitlab.com:team/repo: ["/gitlab/*"]
    YAML

    @org_ignore_config = create(:copilot_content_exclusion_configuration, :organization, resource: @org, document: @org_document)

    @repo_ignore_config = create(:copilot_content_exclusion_configuration, :repository,
      document: <<~YAML
        ["/repo_paths*"]
      YAML
    )
  end

  def rules_resolver_cache_key(document, repo_url)
    "copilot:ignore:rules_resolver:#{Digest::SHA256.hexdigest(document)}:#{Digest::SHA256.hexdigest(repo_url)}"
  end

  context "#resolve_rules_for_repo_url" do
    test "does not fail if unsupported rule is present" do
      config = create(:copilot_content_exclusion_configuration, :organization, document: <<~YAML)
        git@git.com:team/repo: ["repo"]
      YAML

      rules = config.resolve_rules_for_repo_url("/users/maraisr/repo")
      assert_equal rules.collect(&:patterns).flatten.sort, []
    end

    context "with an organization" do
      test "finds path for git repo" do
        rules = @org_ignore_config.resolve_rules_for_repo_url("git@gitlab.com:team/repo")
        assert_equal ["/gitlab/*", "/gitlab/*", "/wildcard-path/*"], rules.collect(&:patterns).flatten.sort
      end

      test "finds for name-with-owner style lookup" do
        rules = @org_ignore_config.resolve_rules_for_repo_url("git@github.com:#{@org_ignore_config.resource.name}/smile")
        assert_equal ["/smile*", "/wildcard-path/*"], rules.collect(&:patterns).flatten.sort
      end

      test "gets rules from the cache" do
        repo_url = "git@gitlab.com:team/repo"
        valid_rules = ["/wildcard-path/*", "/gitlab/*", "/gitlab/*"]

        Copilot.redis.set(rules_resolver_cache_key(@org_document, repo_url), valid_rules)

        rules = @org_ignore_config.resolve_rules_for_repo_url(repo_url)

        assert_equal valid_rules, rules.map(&:patterns).flatten
      end

      test "gets rules when cache is empty and sets the cache" do
        repo_url = "git@gitlab.com:team/repo"
        valid_rules = ["/wildcard-path/*", "/gitlab/*", "/gitlab/*"]

        Copilot.redis.flushdb

        rules = @org_ignore_config.resolve_rules_for_repo_url(repo_url)

        assert_equal valid_rules, rules.map(&:patterns).flatten
      end

      test "gets rules when cache returns an invalid value and resets the cache" do
        repo_url = "git@gitlab.com:team/repo"
        valid_rules = ["/wildcard-path/*", "/gitlab/*", "/gitlab/*"]

        Copilot.redis.set(rules_resolver_cache_key(@org_document, repo_url), "invalid json")

        rules = @org_ignore_config.resolve_rules_for_repo_url(repo_url)

        assert_equal valid_rules, rules.map(&:patterns).flatten
      end

      test "gets rules when the cache is not working" do
        repo_url = "git@gitlab.com:team/repo"
        valid_rules = ["/wildcard-path/*", "/gitlab/*", "/gitlab/*"]

        Copilot.redis.stubs(:get).raises(Redis::BaseError)

        rules = @org_ignore_config.resolve_rules_for_repo_url(repo_url)

        assert_equal valid_rules, rules.map(&:patterns).flatten
      end
    end

    context "with a repository" do
      test "returns all paths for correct repo_url" do
        rules = @repo_ignore_config.resolve_rules_for_repo_url(@repo_ignore_config.resource.ssh_url_for_api)
        assert_equal ["/repo_paths*"], rules.collect(&:patterns).flatten.sort
      end

      test "does not returns paths for random url" do
        rules = @repo_ignore_config.resolve_rules_for_repo_url("git@gitlab.com:team/repo")
        assert_equal [], rules.collect(&:patterns).flatten.sort
      end

      test "does not fail if the underlying resource is deleted" do
        repo_id = @repo_ignore_config.resource.id
        assert repo_id

        Repositories::Public.get_active_or_deleted!(repo_id).destroy

        assert @repo_ignore_config.reload.resource_id

        rules = @repo_ignore_config.resolve_rules_for_repo_url("git@gitlab.com:team/repo")
        assert_equal [], rules
      end
    end
  end
end if GitHub.copilot_enabled?
