# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../../github_sponsors/app/models/sponsors/k_v"

class Repository::FundingLinksDependencyTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @user = create(:user)

    @user_repo = create(:repository, owner: @user)
    @org_repo  = create(:repository, owner: @org)
    @global_org_repo = create(:repository, owner: @org, name: ".github")
  end

  setup do
    Spokesd.enable_spokesd
    [@user_repo, @org_repo, @global_org_repo].each do |repo|
      RepositoryCheckPreferredFilesJob.perform_now(repo.id, repo.default_oid)
    end
  end

  context "#funding_links_stafftools_disabled?" do
    test "returns true when funding links have been disabled for the repo" do
      Sponsors::KV.store.set(@user_repo.funding_links_stafftools_kv_prefix, "1")
      assert_predicate @user_repo, :funding_links_stafftools_disabled?
    end

    test "returns true when funding links have not been disabled for the repo" do
      Sponsors::KV.store.del(@user_repo.funding_links_stafftools_kv_prefix)
      refute_predicate @user_repo, :funding_links_stafftools_disabled?
    end

    test "can be loaded efficiently for many repositories at once" do
      disabled_repo1, disabled_repo2 = create_pair(:repository)
      Sponsors::KV.store.set(disabled_repo1.funding_links_stafftools_kv_prefix, "1")
      Sponsors::KV.store.set(disabled_repo2.funding_links_stafftools_kv_prefix, "1")

      enabled_repo1, enabled_repo2 = create_pair(:repository)

      repos = [disabled_repo1, disabled_repo2, enabled_repo1, enabled_repo2]

      assert_query_count_per_table({ sponsors_key_values: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(repos, :funding_links_stafftools_disabled?)
      end

      assert_query_count(0) do
        assert_predicate disabled_repo1, :funding_links_stafftools_disabled?
        assert_predicate disabled_repo2, :funding_links_stafftools_disabled?
        refute_predicate enabled_repo1, :funding_links_stafftools_disabled?
        refute_predicate enabled_repo2, :funding_links_stafftools_disabled?
      end
    end
  end

  context "#can_enable_repository_funding_links?" do
    if GitHub.enterprise?
      test "false for enterprise installations" do
        refute_predicate @user_repo, :can_enable_repository_funding_links?
      end
    else
      test "false for repositories of trade controls restricted users" do
        @user_repo.owner.trade_controls_restriction.full!

        assert @user_repo.has_any_trade_restrictions?
        refute_predicate @user_repo, :can_enable_repository_funding_links?
      end

      test "true for repositories that are not trade restricted" do
        assert_predicate @user_repo, :can_enable_repository_funding_links?
      end
    end
  end

  context "#repository_funding_links_enabled?" do
    test "returns true when funding links have been enabled for the repository" do
      @user_repo.enable_repository_funding_links(actor: @user)
      assert_predicate @user_repo, :repository_funding_links_enabled?
    end

    test "returns false when funding links have been disabled for the repository" do
      @user_repo.disable_repository_funding_links(actor: @user)
      refute_predicate @user_repo, :repository_funding_links_enabled?
    end

    test "returns true when a funding file exists in a non-fork repo and the setting is unset" do
      repo = create(:repository_preferred_file, :funding).repository
      assert_predicate repo, :has_funding_file?, "need a repo with a funding file"

      assert_predicate repo, :repository_funding_links_enabled?
    end

    test "returns false when a funding file exists in a fork repo and the setting is unset" do
      repo = create(:repository_preferred_file, :funding).repository
      example_repo :funding_links, repo # rubocop:disable GitHub/UseFromExampleInRepositoryFactory
      assert_predicate repo, :has_funding_file?, "need a repo with a funding file"

      fork_owner = create(:user)
      fork_repo = create(:fork_repository, forker: fork_owner, fork_repo: repo)
      create(:repository_preferred_file, :funding, repository: fork_repo)

      refute_predicate fork_repo, :repository_funding_links_enabled?
    end

    test "returns true when a funding file is inherited and the setting is enabled on the global funding file repo" do
      example_repo :funding_file_top_level, @global_org_repo
      another_org_repo = create(:repository, owner: @org)

      RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)
      RepositoryCheckPreferredFilesJob.perform_now(another_org_repo.id, another_org_repo.default_oid)

      # Look up repo again to clear memoized `preferred_files`:
      another_org_repo = Repositories::Public.find_active!(another_org_repo.id)
      assert_predicate another_org_repo, :inheriting_global_funding_file?,
        "need a repo inheriting from a global funding file"

      assert_predicate another_org_repo, :repository_funding_links_enabled?
    end

    test "can be efficiently loaded for multiple repos" do
      enabled_repo1, enabled_repo2 = create_pair(:repository, owner: @user)
      enabled_repo1.enable_repository_funding_links(actor: @user)
      enabled_repo2.enable_repository_funding_links(actor: @user)

      source_repo = create(:repository_preferred_file, :funding).repository
      example_repo :funding_links, source_repo # rubocop:disable GitHub/UseFromExampleInRepositoryFactory
      fork_owner = create(:user)
      fork_repo = create(:fork_repository, forker: fork_owner, fork_repo: source_repo)
      create(:repository_preferred_file, :funding, repository: fork_repo)

      disabled_repo = create(:repository, owner: @user)
      disabled_repo.disable_repository_funding_links(actor: @user)

      example_repo :funding_file_top_level, @global_org_repo
      inherited_repo = create(:repository, owner: @org)
      RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)
      RepositoryCheckPreferredFilesJob.perform_now(inherited_repo.id, inherited_repo.default_oid)

      # Load repos fresh so they don't have any relations or config loaded:
      enabled_repo1 = Repositories::Public.find_active!(enabled_repo1.id)
      enabled_repo2 = Repositories::Public.find_active!(enabled_repo2.id)
      source_repo = Repositories::Public.find_active!(source_repo.id)
      fork_repo = Repositories::Public.find_active!(fork_repo.id)
      disabled_repo = Repositories::Public.find_active!(disabled_repo.id)
      inherited_repo = Repositories::Public.find_active!(inherited_repo.id)

      repos = [enabled_repo1, enabled_repo2, source_repo, fork_repo, disabled_repo, inherited_repo]

      expected_query_counts = {
        configuration_entries: 1,
        preferred_files: 1,
        repositories: 1,
        business_organization_memberships: 1,
        users: 1,
      }

      expected_query_counts[:users] = 2 if TestEnv.test_all_features?
      expected_query_counts[:business_organization_memberships] = 2 if TestEnv.test_all_features?
      expected_query_counts[:businesses] = 5 if GitHub.enterprise?
      assert_query_count_per_table(expected_query_counts) do
        GitHub::PrefillAssociations.prefill_batch_method(repos, :repository_funding_links_enabled?)
      end

      assert_query_count(0) do
        assert_predicate enabled_repo1, :repository_funding_links_enabled?
        assert_predicate enabled_repo2, :repository_funding_links_enabled?
        assert_predicate source_repo, :repository_funding_links_enabled?
        assert_predicate inherited_repo, :repository_funding_links_enabled?
        refute_predicate fork_repo, :repository_funding_links_enabled?
        refute_predicate disabled_repo, :repository_funding_links_enabled?
      end
    end
  end

  context "#inheriting_global_funding_file?" do
    test "returns false if current repo does not belong to an org" do
      refute_predicate @user_repo, :inheriting_global_funding_file?
    end

    test "returns false if current repo is global health files repo" do
      refute_predicate @global_org_repo, :inheriting_global_funding_file?
    end

    test "returns false if there's no funding file present" do
      org_repo = create(:org_owned_repository)
      refute_predicate org_repo, :inheriting_global_funding_file?
    end

    test "returns true if preferred_funding references a funding file in the global repo" do
      example_repo :funding_file_top_level, @global_org_repo
      another_org_repo = create(:repository, owner: @org)

      RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)
      RepositoryCheckPreferredFilesJob.perform_now(another_org_repo.id, another_org_repo.default_oid)

      # Look up repo again to clear memoized `preferred_files`:
      another_org_repo = Repositories::Public.find_active!(another_org_repo.id)
      assert_predicate another_org_repo, :inheriting_global_funding_file?
    end

    test "returns false if preferred_funding references funding file in current repo" do
      example_repo :funding_file_nested, @org_repo
      refute_predicate @org_repo, :inheriting_global_funding_file?
    end

    test "can be efficiently loaded for multiple repos at once" do
      org_repo = create(:org_owned_repository)

      example_repo :funding_file_top_level, @global_org_repo
      RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)

      inheriting_repo1 = create(:repository, owner: @org)
      RepositoryCheckPreferredFilesJob.perform_now(inheriting_repo1.id, inheriting_repo1.default_oid)

      inheriting_repo2 = create(:repository, owner: @org)
      RepositoryCheckPreferredFilesJob.perform_now(inheriting_repo2.id, inheriting_repo2.default_oid)

      # Look up repositories again to ensure no relations are already loaded:
      @user_repo = Repositories::Public.find_active!(@user_repo.id)
      @global_org_repo = Repositories::Public.find_active!(@global_org_repo.id)
      org_repo = Repositories::Public.find_active!(org_repo.id)
      inheriting_repo1 = Repositories::Public.find_active!(inheriting_repo1.id)
      inheriting_repo2 = Repositories::Public.find_active!(inheriting_repo2.id)

      repos = [@user_repo, @global_org_repo, org_repo, inheriting_repo1, inheriting_repo2]

      assert_query_count_per_table({
        repositories: 1,
        repository_networks: 1,
        preferred_files: 1,
      }) do
        GitHub::PrefillAssociations.prefill_batch_method(repos, :inheriting_global_funding_file?)
      end

      assert_query_count(0) do
        refute_predicate @user_repo, :inheriting_global_funding_file?
        refute_predicate @global_org_repo, :inheriting_global_funding_file?
        refute_predicate org_repo, :inheriting_global_funding_file?
        assert_predicate inheriting_repo1, :inheriting_global_funding_file?
        assert_predicate inheriting_repo2, :inheriting_global_funding_file?
      end
    end
  end

  context "#overriding_global_funding_file?" do
    test "returns false if current repo does not belong to an org" do
      refute_predicate @user_repo, :overriding_global_funding_file?
    end

    test "returns false if current repo is global health files repo" do
      refute_predicate @global_org_repo, :overriding_global_funding_file?
    end

    test "returns false if there's no global funding file present in org" do
      repo = create(:repository)
      create(:repository_preferred_file, :funding)

      refute_predicate repo, :overriding_global_funding_file?
    end

    test "returns true if preferred_funding is not the global funding file" do
      example_repo :funding_file_top_level, @global_org_repo
      example_repo :funding_file_nested, @org_repo
      assert_predicate @org_repo, :overriding_global_funding_file?
    end

    test "returns false if preferred_funding is the global funding file" do
      example_repo :funding_file_top_level, @global_org_repo
      another_org_repo = create(:repository, owner: @org)

      [another_org_repo, @global_org_repo].each do |repo|
        RepositoryCheckPreferredFilesJob.perform_now(repo.id, repo.default_oid)
      end

      # Look up repo again to clear memoized `preferred_files`:
      another_org_repo = Repositories::Public.find_active!(another_org_repo.id)
      refute_predicate another_org_repo, :overriding_global_funding_file?
    end
  end

  context "#funding_links_path" do
    test "returns default .github/FUNDING.yml path for a repo with no local funding file" do
      empty_user_repo = create(:repository, owner: @user)
      empty_org_repo  = create(:repository, owner: @org)

      assert_equal ".github/FUNDING.yml", empty_user_repo.funding_links_path
      assert_equal ".github/FUNDING.yml", empty_org_repo.funding_links_path
    end

    test "returns correct path for funding file in a .github directory" do
      example_repo :funding_file_nested, @user_repo
      example_repo :funding_file_nested, @org_repo

      assert_equal ".github/FUNDING.yml", @user_repo.funding_links_path
      assert_equal ".github/FUNDING.yml", @org_repo.funding_links_path
    end

    test "returns correct path for funding file in the root directory" do
      example_repo :funding_file_top_level, @user_repo
      example_repo :funding_file_top_level, @org_repo

      assert_equal "FUNDING.yml", @user_repo.funding_links_path
      assert_equal "FUNDING.yml", @org_repo.funding_links_path
    end

    test "returns correct path for funding file in the docs directory" do
      example_repo :funding_file_docs_directory, @user_repo
      example_repo :funding_file_docs_directory, @org_repo

      assert_equal "docs/FUNDING.yml", @user_repo.funding_links_path
      assert_equal "docs/FUNDING.yml", @org_repo.funding_links_path
    end
  end

  context "#global_funding_file_repository_funding_links_enabled?" do
    test "returns true when repo's global org repo has funding links explicitly enabled and has a funding file" do
      example_repo :funding_file_top_level, @global_org_repo
      RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)
      @global_org_repo.enable_repository_funding_links(actor: @org.admin)
      another_org_repo = create(:repository, owner: @org)
      assert_predicate another_org_repo, :global_funding_file_repository_funding_links_enabled?
    end

    test "returns true when repo's global org repo is not a fork and has a funding file and setting is unset" do
      example_repo :funding_file_top_level, @global_org_repo
      RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)
      another_org_repo = create(:repository, owner: @org)
      assert_predicate another_org_repo, :global_funding_file_repository_funding_links_enabled?
    end

    test "returns false when repo's global org repo is a fork with a funding file and setting is unset" do
      example_repo :funding_file_top_level, @global_org_repo
      other_org = create(:organization)
      global_org_repo_fork = create(:fork_repository, organization: other_org, fork_repo: @global_org_repo, forker: other_org.admins.first)
      RepositoryCheckPreferredFilesJob.perform_now(global_org_repo_fork.id, global_org_repo_fork.default_oid)
      another_org_repo = create(:repository, owner: other_org)
      refute_predicate another_org_repo, :global_funding_file_repository_funding_links_enabled?
    end

    test "returns false when repo's global org repo has a funding file but has funding links explicitly disabled" do
      example_repo :funding_file_top_level, @global_org_repo
      RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)
      @global_org_repo.disable_repository_funding_links(actor: @org.admin)
      another_org_repo = create(:repository, owner: @org)
      refute_predicate another_org_repo, :global_funding_file_repository_funding_links_enabled?
    end

    test "returns false for repo without a global org repo" do
      org = create(:organization)
      another_org_repo = create(:repository, owner: org)
      refute_predicate another_org_repo, :global_funding_file_repository_funding_links_enabled?
    end

    test "can be loaded efficiently for many repositories at once" do
      example_repo :funding_file_top_level, @global_org_repo
      RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)
      another_org_repo = create(:repository, owner: @org)

      other_org = create(:organization)
      global_org_repo_fork = create(:fork_repository, organization: other_org, fork_repo: @global_org_repo, forker: other_org.admins.first)
      RepositoryCheckPreferredFilesJob.perform_now(global_org_repo_fork.id, global_org_repo_fork.default_oid)
      another_other_org_repo = create(:repository, owner: other_org)

      repo_without_global_org_repo = create(:repository)

      # Look repos up fresh so no relations are loaded on them yet:
      another_org_repo = Repositories::Public.find_active!(another_org_repo.id)
      another_other_org_repo = Repositories::Public.find_active!(another_other_org_repo.id)
      repo_without_global_org_repo = Repositories::Public.find_active!(repo_without_global_org_repo.id)

      repos = [another_org_repo, another_other_org_repo, repo_without_global_org_repo]

      expected_query_counts = if TestEnv.test_all_features?
        {
          configuration_entries: 1,
          repositories: 2,
          preferred_files: 1,
          users: 2,
        }
      else
        {
          configuration_entries: 1,
          repositories: 2,
          preferred_files: 1,
          business_organization_memberships: 1,
          users: 1,
        }
      end

      assert_query_count_per_table(expected_query_counts) do
        GitHub::PrefillAssociations.prefill_batch_method(repos,
          :global_funding_file_repository_funding_links_enabled?)
      end

      assert_query_count(0) do
        assert_predicate another_org_repo, :global_funding_file_repository_funding_links_enabled?
        refute_predicate another_other_org_repo, :global_funding_file_repository_funding_links_enabled?
        refute_predicate repo_without_global_org_repo, :global_funding_file_repository_funding_links_enabled?
      end
    end
  end

  context "#funding_links_to_hydro" do
    test "returns [] when the file doesn't exist" do
      user = create(:user)
      repo = create(:repository, owner: user)
      assert_empty repo.funding_links_to_hydro
    end

    test "returns funding links" do
      example_repo :funding_links, @org_repo
      create(:user, :sponsorable, login: "monalisa")

      expected = [
        { platform_type: "GITHUB", platform_url: "https://github.com/monalisa" },
        { platform_type: "PATREON", platform_url: "https://patreon.com/patreon-testing-username-github" },
        { platform_type: "OPEN_COLLECTIVE", platform_url: "https://opencollective.com/opencollective-testing-username" },
        { platform_type: "KO_FI", platform_url: "https://ko-fi.com/ko-fi-testing-username" },
        { platform_type: "TIDELIFT", platform_url: "https://tidelift.com/funding/github/tidelift-testing-username" },
        { platform_type: "COMMUNITY_BRIDGE", platform_url: "https://funding.communitybridge.org/projects/community-bridge-testing-username" },
        { platform_type: "LIBERAPAY", platform_url: "https://liberapay.com/liberapay-testing-username" },
        { platform_type: "ISSUEHUNT", platform_url: "https://issuehunt.io/r/issuehunt-testing-username" },
        { platform_type: "LFX_CROWDFUNDING", platform_url: "https://crowdfunding.lfx.linuxfoundation.org/projects/lfx-crowdfunding-testing-username" },
        { platform_type: "POLAR", platform_url: "https://polar.sh/polar-testing-username" },
        { platform_type: "BUY_ME_A_COFFEE", platform_url: "https://buymeacoffee.com/buy-me-a-coffee-testing-username" },
        { platform_type: "THANKS_DEV", platform_url: "https://thanks.dev/thanks-dev-testing-username" },
        { platform_type: "CUSTOM", platform_url: "https://custom.testing" },
      ]

      assert_equal expected, @org_repo.funding_links_to_hydro
    end

    test "returns multiple github funding links if file has array of users" do
      example_repo :funding_links_with_sponsorables, @org_repo
      create(:user, :sponsorable, login: "monalisa")
      create(:user, :sponsorable, login: "mikekavouras")

      expected = [
        { platform_type: "GITHUB", platform_url: "https://github.com/monalisa" },
        { platform_type: "GITHUB", platform_url: "https://github.com/mikekavouras" },
        { platform_type: "PATREON", platform_url: "https://patreon.com/patreon-testing-username-github" },
        { platform_type: "OPEN_COLLECTIVE", platform_url: "https://opencollective.com/opencollective-testing-username" },
      ]

      assert_equal expected, @org_repo.funding_links_to_hydro
    end

    test "does not return github sponsors if users are not sponsorable" do
      example_repo :funding_links_with_sponsorables, @org_repo

      expected = [
        { platform_type: "PATREON", platform_url: "https://patreon.com/patreon-testing-username-github" },
        { platform_type: "OPEN_COLLECTIVE", platform_url: "https://opencollective.com/opencollective-testing-username" },
      ]

      assert_equal expected, @org_repo.funding_links_to_hydro
    end
  end
end
