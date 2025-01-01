# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../../../packages/github_sponsors/app/models/sponsors/k_v"

class RepositorySponsorsDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @listing = create(:sponsors_listing, sponsorable: @repo.owner)

    # Ensure there's a global business created
    create(:business)

    @potential_sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
    @sponsorable = create(:user, :sponsorable)
    @sponsorable_repo = create(:repository_sponsorable, :owner, sponsorable: @sponsorable).repository

    @user = create(:user)
    @user_repo = create(:repository, owner: @user)
    @global_org = create(:organization)
    @global_org_repo = create(:repository, owner: @global_org, name: ".github")
  end

  setup do
    Spokesd.enable_spokesd
  end

  context "owner_sponsors_listing_stafftools_metadata relation" do
    test "returns the Sponsors stafftools metadata record for the repo's owner" do
      stafftools_metadata = create(:sponsors_listing_stafftools_metadata)
      user = stafftools_metadata.sponsorable
      repository = create(:repository, owner: user)
      assert_equal stafftools_metadata, repository.owner_sponsors_listing_stafftools_metadata
    end

    test "returns nil when repo's owner does not exist" do
      repository = create(:repository)
      repository.owner.delete
      assert_nil repository.owner_sponsors_listing_stafftools_metadata
    end

    test "returns nil when no Sponsors stafftools metadata record exists for the repo's owner" do
      repository = create(:repository)
      assert_nil repository.owner_sponsors_listing_stafftools_metadata
    end
  end

  context "owner_repository_sponsorable relation" do
    test "returns the RepositorySponsorable record for the repo's owner when it exists" do
      repo_sponsorable = create(:repository_sponsorable, :owner)
      repo = repo_sponsorable.repository
      assert_equal repo_sponsorable, repo.owner_repository_sponsorable
    end

    test "returns nil when repo only has a repo-sponsorable for a funding file" do
      repo_sponsorable = create(:repository_sponsorable, :funding_file)
      repo = repo_sponsorable.repository
      assert_nil repo.owner_repository_sponsorable
    end

    test "returns nil when repo only has a repo-sponsorable for a global funding file" do
      repo_sponsorable = create(:repository_sponsorable, :global_funding_file)
      repo = repo_sponsorable.repository
      assert_nil repo.owner_repository_sponsorable
    end

    test "returns nil when repo has no repo-sponsorables" do
      repo = create(:repository)
      assert_nil repo.owner_repository_sponsorable
    end
  end

  context "sponsorable scope" do
    test "includes repo with sponsorable owner" do
      repo_sponsorable = create(:repository_sponsorable, :owner)
      repo = repo_sponsorable.repository
      assert_equal [repo], Repository.where(id: repo).sponsorable
    end

    test "includes repo with a sponsorable in the funding file but whose owner is not sponsorable" do
      repo_sponsorable = create(:repository_sponsorable, :funding_file)
      repo = repo_sponsorable.repository
      assert_equal [repo], Repository.where(id: repo).sponsorable
    end

    test "includes repo with a sponsorable in the funding file and whose owner is also sponsorable" do
      owner_repo_sponsorable = create(:repository_sponsorable, :owner)
      repo = owner_repo_sponsorable.repository
      create(:repository_preferred_file, :funding, repository: repo)
      create(:repository_sponsorable, :funding_file, repository: repo)
      assert_equal [repo], Repository.where(id: repo).sponsorable
    end

    test "includes repo with a sponsorable in the global funding file but whose owner is not sponsorable" do
      global_repo_sponsorable = create(:repository_sponsorable, :global_funding_file)
      repo = global_repo_sponsorable.repository
      assert_equal [repo], Repository.where(id: repo).sponsorable
    end

    test "includes repo with a sponsorable in the global funding file and whose owner is also sponsorable" do
      org = create(:organization, :sponsorable)
      create(:repository, owner: org, name: Repository::GLOBAL_HEALTH_FILES_NAME, from_example: :funding_links)
      repo = create(:repository, owner: org)
      create(:repository_sponsorable, :global_funding_file, repository: repo)
      create(:repository_sponsorable, :owner, repository: repo, sponsorable: org)
      assert_equal [repo], Repository.where(id: repo).sponsorable
    end

    test "omits repo who has no associated sponsorable users or orgs" do
      repo = create(:repository)
      assert_empty Repository.where(id: repo).sponsorable
    end
  end

  context "represented_by_sponsorable scope" do
    test "includes repo with specified sponsorable owner" do
      repo_sponsorable = create(:repository_sponsorable, :owner)
      repo = repo_sponsorable.repository
      assert_equal [repo], Repository.represented_by_sponsorable(repo_sponsorable.sponsorable_id)
    end

    test "includes repo associated with specified non-owner sponsorable" do
      repo_sponsorable = create(:repository_sponsorable, :funding_file)
      repo = repo_sponsorable.repository
      assert_equal [repo], Repository.represented_by_sponsorable(repo_sponsorable.sponsorable_id)

      global_repo_sponsorable = create(:repository_sponsorable, :global_funding_file)
      repo = global_repo_sponsorable.repository
      assert_equal [repo], Repository.represented_by_sponsorable(global_repo_sponsorable.sponsorable_id)
    end

    test "omits repo when specified sponsorable does not match" do
      repo_sponsorable = create(:repository_sponsorable, :funding_file)
      repo = repo_sponsorable.repository
      assert_empty Repository.represented_by_sponsorable(repo.owner_id)
    end

    test "omits repo who has no associated sponsorable users or orgs" do
      repo = create(:repository)
      assert_empty Repository.represented_by_sponsorable(repo.owner_id)
    end

    test "returns an empty list when no sponsorable is passed" do
      assert_empty Repository.represented_by_sponsorable(nil)
    end

    test "returns a list of unique repositories" do
      sponsorable = create(:user, :sponsorable)
      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      create(:repository_preferred_file, :funding, repository: dependency)
      create(:repository_sponsorable, :funding_file, sponsorable: sponsorable, repository: dependency)

      assert_equal [dependency], Repository.represented_by_sponsorable(sponsorable.id)
    end
  end

  context "with_sponsorable_owner scope" do
    test "includes repo with sponsorable owner" do
      repo_sponsorable = create(:repository_sponsorable, :owner)
      repo = repo_sponsorable.repository
      assert_equal [repo], Repository.where(id: repo).with_sponsorable_owner
    end

    test "omits repo who has someone else sponsorable besides the owner" do
      repo_sponsorable = create(:repository_sponsorable, :funding_file)
      assert_empty Repository.where(id: repo_sponsorable.repository_id).with_sponsorable_owner

      global_repo_sponsorable = create(:repository_sponsorable, :global_funding_file)
      assert_empty Repository.where(id: global_repo_sponsorable.repository_id).with_sponsorable_owner
    end

    test "works with scope off a topic" do
      topic = create(:topic)
      repo_sponsorable = create(:repository_sponsorable, :owner)
      repo = repo_sponsorable.repository
      create(:repository_topic, topic: topic, repository: repo)
      assert_equal [repo], topic.repositories.with_sponsorable_owner
    end
  end

  context "sponsorship_repositories association" do
    test "destroys sponsorship repo records when repo is destroyed" do
      sponsorship_repo = create(:sponsorship_repository)
      repo = sponsorship_repo.repository
      assert_equal [sponsorship_repo], repo.sponsorship_repositories

      assert_difference -> { SponsorshipRepository.count }, -1 do
        assert repo.destroy
      end

      assert_empty repo.sponsorship_repositories
    end
  end

  context "repository_sponsorables association" do
    test "destroys repo sponsorable records when repo is destroyed" do
      approved_listing = create(:sponsors_listing, :approved)
      repo = create(:repository, owner: approved_listing.sponsorable)
      repo_sponsorable = create(:repository_sponsorable, sponsorable: approved_listing.sponsorable, repository: repo,
        source: :owner)

      assert_difference(-> { RepositorySponsorable.count }, -1) do
        repo.destroy!
      end

      refute RepositorySponsorable.exists?(repo_sponsorable.id)
    end
  end

  context "sponsors_listing_featured_items association" do
    test "destroys featured items when repo is destroyed" do
      @listing.featured_items.create(featureable: @repo)

      assert_predicate @repo.reload.sponsors_listing_featured_items, :one?
      assert_predicate @listing.reload.featured_items, :one?

      assert_difference -> { SponsorsListingFeaturedItem.count }, -1 do
        @repo.destroy
      end

      assert_predicate @listing.reload.featured_items, :empty?
    end

    test "destroys featured items when repo is transfered" do
      other_org = create(:organization)
      @listing.featured_items.create(featureable: @repo)

      assert_predicate @repo.reload.sponsors_listing_featured_items, :one?
      assert_predicate @listing.reload.featured_items, :one?

      assert_difference -> { SponsorsListingFeaturedItem.count }, -1 do
        @repo.transfer_ownership_to(other_org, actor: @repo.owner)
      end

      assert_predicate @listing.reload.featured_items, :empty?
    end

    test "can still transfer ownership even if no featured item exists" do
      other_org = create(:organization)

      assert_predicate @repo.reload.sponsors_listing_featured_items, :empty?
      assert_predicate @listing.reload.featured_items, :empty?
      assert @repo.transfer_ownership_to(other_org, actor: @repo.owner)
    end

    test "destroys featured items when repo is made private" do
      @listing.featured_items.create(featureable: @repo)

      assert_predicate @repo.reload.sponsors_listing_featured_items, :one?
      assert_predicate @listing.reload.featured_items, :one?

      assert_difference -> { SponsorsListingFeaturedItem.count }, -1 do
        @repo.toggle_visibility(actor: @repo.owner)
      end

      assert_predicate @listing.reload.featured_items, :empty?
    end
  end

  context "#sponsorable_owner?" do
    test "returns false if no repo-sponsorable record exists" do
      @sponsorable_repo.owner_repository_sponsorable.delete
      refute_predicate @sponsorable_repo, :sponsorable_owner?
    end

    if GitHub.sponsors_enabled?
      test "returns true if a source=owner repo-sponsorable record exists" do
        refute_nil @sponsorable_repo.owner_repository_sponsorable
        assert_predicate @sponsorable_repo, :sponsorable_owner?
      end

      test "returns false if a source=repo_funding_file repo-sponsorable record exists" do
        repo_sponsorable = create(:repository_sponsorable, :funding_file)
        refute_predicate repo_sponsorable.repository, :sponsorable_owner?
      end

      test "returns false if a source=global_funding_file repo-sponsorable record exists" do
        repo_sponsorable = create(:repository_sponsorable, :global_funding_file)
        refute_predicate repo_sponsorable.repository, :sponsorable_owner?
      end
    else
      test "returns false if owner has an approved Sponsors listing but Sponsors is disabled" do
        refute_predicate @sponsorable_repo, :sponsorable_owner?
      end
    end

    test "can be batch loaded for many repositories" do
      sponsorable_repo1 = create(:repository_sponsorable, :owner).repository
      non_sponsorable_repo1, non_sponsorable_repo2 = create_pair(:repository)
      sponsorable_repo2 = create(:repository_sponsorable, :owner).repository

      # Look up each repo fresh so none of its relations are loaded:
      sponsorable_repo1 = Repositories::Public.get_active_or_deleted(sponsorable_repo1.id)
      non_sponsorable_repo1 = Repositories::Public.get_active_or_deleted(non_sponsorable_repo1.id)
      non_sponsorable_repo2 = Repositories::Public.get_active_or_deleted(non_sponsorable_repo2.id)
      sponsorable_repo2 = Repositories::Public.get_active_or_deleted(sponsorable_repo2.id)

      repos = [sponsorable_repo1, non_sponsorable_repo1, sponsorable_repo2, non_sponsorable_repo2]

      expected_query_count = GitHub.sponsors_enabled? ? 1 : 0
      assert_query_count(expected_query_count) do
        GitHub::PrefillAssociations.prefill_batch_method(repos, :sponsorable_owner?)
      end

      assert_query_count(0) do
        if GitHub.sponsors_enabled?
          assert_predicate sponsorable_repo1, :sponsorable_owner?
          assert_predicate sponsorable_repo2, :sponsorable_owner?
        else
          refute_predicate sponsorable_repo1, :sponsorable_owner?
          refute_predicate sponsorable_repo2, :sponsorable_owner?
        end
        refute_predicate non_sponsorable_repo1, :sponsorable_owner?
        refute_predicate non_sponsorable_repo2, :sponsorable_owner?
      end
    end
  end

  context "#async_owner_sponsored_by_viewer?" do
    test "resolves to false if owner is deleted" do
      @sponsorable.delete # Delete instead of destroy to avoid cleanup callbacks
      refute @sponsorable_repo.reload.async_owner_sponsored_by_viewer?(@potential_sponsor).sync
    end

    test "resolves to false if viewer is not a sponsor" do
      refute @sponsorable_repo.async_owner_sponsored_by_viewer?(@potential_sponsor).sync
    end

    test "resolves to true if owner is a sponsor" do
      create(:sponsorship, sponsor: @potential_sponsor, sponsorable: @sponsorable)

      assert @sponsorable_repo.async_owner_sponsored_by_viewer?(@potential_sponsor).sync
    end
  end

  context "#show_sponsor_button?" do
    if GitHub.enterprise?
      test "false for enterprise" do
        @user_repo.stubs(:repository_funding_links_enabled?).returns(true)
        refute_predicate @user_repo, :show_sponsor_button?
      end
    else
      test "false if the repo owner is trade controls restricted" do
        example_repo :funding_links, @user_repo
        @user_repo.stubs(:repository_funding_links_enabled?).returns(true)
        @user_repo.owner.trade_controls_restriction.full!

        refute_predicate @user_repo, :show_sponsor_button?
      end

      test "false unless repo repository_funding_links_enabled" do
        @user_repo.stubs(:repository_funding_links_enabled?).returns(false)
        refute_predicate @user_repo, :show_sponsor_button?
      end

      test "false if repo has no funding file" do
        other_repo = create(:repository)
        refute_predicate other_repo, :show_sponsor_button?
      end

      test "false if repo has been disabled by stafftools" do
        @user_repo.stubs(:repository_funding_links_enabled?).returns(true)
        Sponsors::KV.store.set(@user_repo.funding_links_stafftools_kv_prefix, "1")
        refute_predicate @user_repo, :show_sponsor_button?
      end

      test "true when not enterprise, funding links enabled, and repo has funding file" do
        example_repo :funding_links, @user_repo
        @user_repo.stubs(:repository_funding_links_enabled?).returns(true)
        assert_predicate @user_repo, :show_sponsor_button?
      end

      test "false if repo is global org repo" do
        example_repo :funding_file_top_level, @global_org_repo
        @global_org_repo.stubs(:repository_funding_links_enabled?).returns(true)
        refute_predicate @global_org_repo, :show_sponsor_button?
      end

      test "false if funding links unset and inheriting from not enabled .github repository" do
        example_repo :funding_file_top_level, @global_org_repo
        another_org_repo = create(:repository, owner: @global_org)

        another_org_repo.stubs(:global_funding_file_repository_funding_links_enabled?).returns(true)
        another_org_repo.stubs(:repository_funding_links_explicitly_enabled?).returns(false)
        another_org_repo.stubs(:repository_funding_links_unset?).returns(true)

        assert_predicate another_org_repo, :show_sponsor_button?
      end

      test "true if funding links unset and inheriting from enabled .github repository" do
        example_repo :funding_file_top_level, @global_org_repo
        another_org_repo = create(:repository, owner: @global_org)

        another_org_repo.stubs(:global_funding_file_repository_funding_links_enabled?).returns(true)
        another_org_repo.stubs(:repository_funding_links_explicitly_enabled?).returns(false)
        another_org_repo.stubs(:repository_funding_links_unset?).returns(true)

        assert_predicate another_org_repo, :show_sponsor_button?
      end

      test "false if funding links set to false and inheriting from enabled .github repository" do
        example_repo :funding_file_top_level, @global_org_repo
        another_org_repo = create(:repository, owner: @global_org)

        another_org_repo.stubs(:global_funding_file_repository_funding_links_enabled?).returns(true)
        another_org_repo.stubs(:repository_funding_links_explicitly_enabled?).returns(false)
        another_org_repo.stubs(:repository_funding_links_unset?).returns(false)

        refute_predicate another_org_repo, :show_sponsor_button?
      end

      test "can be batch loaded on many repos at once" do
        example_repo :funding_file_top_level, @global_org_repo
        RepositoryCheckPreferredFilesJob.perform_now(@global_org_repo.id, @global_org_repo.default_oid)
        another_org_repo = create(:repository, owner: @global_org)

        example_repo :funding_links, @user_repo
        RepositoryCheckPreferredFilesJob.perform_now(@user_repo.id, @user_repo.default_oid)
        @user_repo.enable_repository_funding_links(actor: @user)

        other_repo = create(:repository)

        # Load repos so they don't have any relations loaded already:
        @user_repo = Repositories::Public.find_active!(@user_repo.id)
        another_org_repo = Repositories::Public.find_active!(another_org_repo.id)
        @global_org_repo = Repositories::Public.find_active!(@global_org_repo.id)
        other_repo = Repositories::Public.find_active!(other_repo.id)

        repos = [@user_repo, another_org_repo, @global_org_repo, other_repo]

        assert_query_count_per_table({
          configuration_entries: 2,
          preferred_files: 1,
          repositories: 1,
          users: 2,
          business_organization_memberships: 2,
          repository_networks: 2,
          sponsors_key_values: 1,
          trade_controls_restrictions: 1,
        }) do
          GitHub::PrefillAssociations.prefill_batch_method(repos, :show_sponsor_button?)
        end

        assert_query_count(0) do
          assert_predicate @user_repo, :show_sponsor_button?
          assert_predicate another_org_repo, :show_sponsor_button?
          refute_predicate @global_org_repo, :show_sponsor_button?
          refute_predicate other_repo, :show_sponsor_button?
        end
      end
    end
  end

  if GitHub.sponsors_enabled?
    context "create callbacks" do
      test "enqueues job to update RepositorySponsorable records when owner is sponsorable" do
        sponsorable_owner = create(:user, :sponsorable)
        assert_enqueued_with(
          job: UpdateOwnerRepositorySponsorablesJob,
          args: [{ sponsorable_id: sponsorable_owner.id }],
        ) do
          create(:repository, :full_creation, owner: sponsorable_owner)
        end
      end

      test "does not enqueue job to update RepositorySponsorable records when owner does not have a SponsorsListing" do
        user_without_listing = create(:user)
        assert_no_enqueued_jobs(only: UpdateOwnerRepositorySponsorablesJob) do
          create(:repository, owner: user_without_listing)
        end
      end

      test "does not enqueue job to update RepositorySponsorable records when owner's SponsorsListing is not approved" do
        refute_nil @org.sponsors_listing
        refute_predicate @org.sponsors_listing, :approved?
        assert_no_enqueued_jobs(only: UpdateOwnerRepositorySponsorablesJob) do
          create(:repository, owner: @org)
        end
      end

      test "enqueues job to update RepositorySponsorable records when repo inherits a global funding file" do
        repo_owner = create(:organization, login: "org-with-global-funding-file")
        global_health_files_repo = create(:repository, owner: repo_owner,
          name: Repository::GLOBAL_HEALTH_FILES_NAME, from_example: :funding_file_top_level)
        RepositoryCheckPreferredFilesJob.perform_now(global_health_files_repo.id,
          global_health_files_repo.default_oid)
        assert_predicate global_health_files_repo, :global_health_files_repository?

        new_repo = create(:repository, :full_creation, owner: repo_owner, name: "child-repo")

        assert_enqueued_with(job: UpdateRepositorySponsorablesForRepositoryJob, args: [{ repository_id: new_repo.id }])
      end
    end

    context "#alert_sponsors_listing_has_public_non_fork_repository" do
      test "updates Sponsors listing metadata when a public non-fork is created" do
        listing = create(:sponsors_listing)
        sponsorable = listing.sponsorable
        metadata = listing.stafftools_metadata

        refute_predicate metadata, :has_public_non_fork_repository?
        create(:repository, :full_creation, owner: sponsorable)
        assert_predicate metadata.reload, :has_public_non_fork_repository?
      end

      test "does not update Sponsors listing metadata when has_public_non_fork_repository is already true" do
        SponsorsListingStafftoolsMetadata.any_instance.expects(:update_column).never

        metadata = @listing.stafftools_metadata

        assert_predicate metadata, :has_public_non_fork_repository?
        create(:repository, owner: @sponsorable)
        assert_predicate metadata.reload, :has_public_non_fork_repository?
      end

      test "does not update Sponsors listing metadata when a private repo is created" do
        SponsorsListingStafftoolsMetadata.any_instance.expects(:update_column).never

        listing = create(:sponsors_listing)
        sponsorable = listing.sponsorable
        metadata = listing.stafftools_metadata

        refute_predicate metadata, :has_public_non_fork_repository?
        create(:private_repository, owner: sponsorable)
        refute_predicate metadata.reload, :has_public_non_fork_repository?
      end

      test "does not update Sponsors listing metadata when a fork is created" do
        SponsorsListingStafftoolsMetadata.any_instance.expects(:update_column).never

        listing = create(:sponsors_listing)
        sponsorable = listing.sponsorable
        metadata = listing.stafftools_metadata

        refute_predicate metadata, :has_public_non_fork_repository?

        source_repo = create(:repository)
        forked_repo = create(:fork_repository, forker: sponsorable, fork_repo: source_repo)
        refute_nil forked_repo

        refute_predicate metadata.reload, :has_public_non_fork_repository?
      end
    end
  end
end
