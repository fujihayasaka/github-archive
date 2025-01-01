# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsExploreLoaderTest < GitHub::TestCase
  fixtures do
    @sponsorable_dependency1 = create(:repository_sponsorable, :owner).repository
    @sponsorable_owner1 = @sponsorable_dependency1.owner

    @sponsorable_dependency2 = create(:repository_sponsorable, :owner).repository
    @sponsorable_owner2 = @sponsorable_dependency2.owner

    @private_sponsorable_dependency = create(:private_repository, owner: @sponsorable_owner1)
    create(:repository_sponsorable, :owner, sponsorable: @sponsorable_owner1,
      repository: @private_sponsorable_dependency)

    @non_sponsorable_dependency = create(:repository)

    @private_non_sponsorable_dependency = create(:private_repository)

    @org_admin = create(:user)
    @org = create(:organization, :sponsorable, admin: @org_admin)
    @org_repo = create(:repository_sponsorable, :owner, sponsorable: @org).repository
  end

  def new_sponsorable_dependency_owner
    dependency = create(:repository_sponsorable, :owner).repository
    fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
      data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
    })
    DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
    dependency.owner
  end

  context "#account_login" do
    test "returns viewer's login when no org is specified" do
      viewer = create(:user)
      loader = SponsorsExploreLoader.new(viewer: viewer)
      assert_equal viewer.login, loader.account_login
    end

    test "returns org's login when org is specified" do
      org = create(:organization)
      loader = SponsorsExploreLoader.new(viewer: org.admin, org: org)
      assert_equal org.login, loader.account_login
    end
  end

  context "#total_associated_dependencies" do
    test "returns a count of how many of the account's public dependencies the specified user is associated with" do
      sponsorable1, sponsorable2 = create_pair(:user, :sponsorable)
      dependency1, dependency2 = create_pair(:repository, owner: sponsorable1)
      private_dependency = create(:private_repository, owner: sponsorable1) # shouldn't be counted
      create(:repository_sponsorable, :owner, repository: dependency1, sponsorable: sponsorable1)
      create(:repository_sponsorable, :owner, repository: dependency2, sponsorable: sponsorable1)
      create(:repository_sponsorable, :owner, repository: private_dependency, sponsorable: sponsorable1)
      dependency3 = create(:repository, owner: sponsorable2)
      create(:repository_sponsorable, :owner, repository: dependency3, sponsorable: sponsorable2)
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency1, dependency2, dependency3].map(&:id) } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      viewer = create(:user)
      loader = SponsorsExploreLoader.new(viewer: viewer)

      assert_equal 2, loader.total_associated_dependencies(sponsorable1)
      assert_equal 1, loader.total_associated_dependencies(sponsorable2)
    end

    # https://github.com/github/sponsors/issues/2031
    test "omits the viewer" do
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [@sponsorable_dependency1.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      loader = SponsorsExploreLoader.new(viewer: @sponsorable_owner1)

      assert_nil loader.total_associated_dependencies(@sponsorable_owner1)
    end
  end

  context "#paginated_dependencies_represented_by_sponsorable" do
    test "returns a paginated collection of public repositories for a given sponsorable" do
      sponsorable1, sponsorable2 = create_pair(:user, :sponsorable)
      dependency1, dependency2 = create_pair(:repository_sponsorable, :owner,
        sponsorable: sponsorable1).map(&:repository)

      # Dependency by another owner, should not be returned by #paginated_dependencies_represented_by_sponsorable:
      dependency3 = create(:repository_sponsorable, :owner, sponsorable: sponsorable2).repository

      # Dependency owned by someone else but that has the sponsorable in the associated global funding file;
      # should be included:
      dependency4 = create(:repository_sponsorable, :global_funding_file, sponsorable: sponsorable1).repository

      # Private dependency should be excluded:
      private_dependency = create(:private_repository, owner: sponsorable1)
      create(:repository_sponsorable, :owner, repository: private_dependency, sponsorable: sponsorable1)

      dependency_ids = [dependency1, dependency2, dependency3, dependency4, private_dependency].map(&:id)
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: dependency_ids } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      viewer = create(:user)

      filter_set = SponsorsExploreFilterSet.new(per_page: 2)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)
      page1 = loader.paginated_dependencies_represented_by_sponsorable(sponsorable1.id)

      assert_equal [dependency1, dependency2], page1
      assert_equal 2, page1.total_pages

      filter_set = SponsorsExploreFilterSet.new(per_page: 2, page: 2)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)
      page2 = loader.paginated_dependencies_represented_by_sponsorable(sponsorable1.id)

      assert_equal [dependency4], page2
      assert_equal 2, page2.total_pages
    end

    test "includes each dependency only once" do
      viewer = create(:user)

      sponsorable = create(:user, :sponsorable)
      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      create(:repository_preferred_file, :funding, repository: dependency)
      create(:repository_sponsorable, :funding_file, sponsorable: sponsorable, repository: dependency)

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      filter_set = SponsorsExploreFilterSet.new(per_page: 3)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)

      results = loader.paginated_dependencies_represented_by_sponsorable(sponsorable.id)

      assert_equal [dependency.id], results.map(&:id)
    end

    # https://github.com/github/sponsors/issues/2031
    test "omits the viewer themselves" do
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [@sponsorable_dependency1.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: @sponsorable_owner1)
      assert_empty loader.paginated_dependencies_represented_by_sponsorable(@sponsorable_owner1.id)
    end
  end

  context "#sponsorables_from_dependencies" do
    test "returns a list of sponsorables associated with the account's dependencies" do
      sponsorable1, sponsorable2, sponsorable3 = create_list(:user, 3, :sponsorable)

      dependency1, dependency2 = create_pair(:repository, owner: sponsorable1)
      create(:repository_sponsorable, :owner, repository: dependency1, sponsorable: sponsorable1)
      create(:repository_sponsorable, :owner, repository: dependency2, sponsorable: sponsorable1)

      dependency3 = create(:repository, owner: sponsorable2)
      create(:repository_sponsorable, :owner, repository: dependency3, sponsorable: sponsorable2)
      create(:repository_preferred_file, :funding, repository: dependency3)
      create(:repository_sponsorable, :funding_file, repository: dependency3, sponsorable: sponsorable3)

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency1, dependency2, dependency3].map(&:id) } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      viewer = create(:user)
      filter_set = SponsorsExploreFilterSet.new(per_page: 2)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)

      results = loader.sponsorables_from_dependencies

      assert_equal [sponsorable1, sponsorable2, sponsorable3], results
    end
  end

  context "#paginated_sponsorables_from_dependencies" do
    test "returns a paginated list of sponsorables associated with the account's dependencies" do
      sponsorable1, sponsorable2, sponsorable3 = create_list(:user, 3, :sponsorable)

      dependency1, dependency2 = create_pair(:repository, owner: sponsorable1)
      create(:repository_sponsorable, :owner, repository: dependency1, sponsorable: sponsorable1)
      create(:repository_sponsorable, :owner, repository: dependency2, sponsorable: sponsorable1)

      dependency3 = create(:repository, owner: sponsorable2)
      create(:repository_sponsorable, :owner, repository: dependency3, sponsorable: sponsorable2)
      create(:repository_preferred_file, :funding, repository: dependency3)
      create(:repository_sponsorable, :funding_file, repository: dependency3, sponsorable: sponsorable3)

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency1, dependency2, dependency3].map(&:id) } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      viewer = create(:user)

      filter_set = SponsorsExploreFilterSet.new(per_page: 2)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)
      page1 = loader.paginated_sponsorables_from_dependencies

      assert_equal [sponsorable1, sponsorable2], page1
      assert_equal 2, page1.total_pages

      filter_set = SponsorsExploreFilterSet.new(per_page: 2, page: 2)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)
      page2 = loader.paginated_sponsorables_from_dependencies

      assert_equal [sponsorable3], page2
      assert_equal 2, page2.total_pages
    end

    test "loads full results across batches of repository-sponsorables" do
      viewer = create(:user)
      filter_set = SponsorsExploreFilterSet.new(per_page: 10)
      sponsorable1, sponsorable2 = create_pair(:user, :sponsorable)
      dependency1 = create(:repository_sponsorable, :owner, sponsorable: sponsorable1).repository
      dependency2 = create(:repository_sponsorable, :funding_file, sponsorable: sponsorable2).repository

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency1, dependency2].map(&:id) } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      results = SponsorsExploreLoader.stub_const(:BATCH_SIZE, 1) do
        loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)
        loader.paginated_sponsorables_from_dependencies
      end

      assert_equal [sponsorable1, sponsorable2], results
    end

    test "sorts with the maintainer with the fewest sponsors first when specified" do
      user_with_1 = create(:user, :sponsorable, login: "maintainer-with-1-sponsor")
      user_with_0 = create(:user, :sponsorable, login: "maintainer-without-sponsors")
      user_with_2 = create(:user, :sponsorable, login: "maintainer-with-2-sponsors")

      create(:sponsorship, sponsorable: user_with_1)
      create(:sponsorship, sponsorable: user_with_2)
      create(:sponsorship, :private, sponsorable: user_with_2)

      refute_nil user_with_1.reload_user_metadata, "expected user with 1 sponsor to have a UserMetadata record"
      refute_nil user_with_2.reload_user_metadata, "expected user with 2 sponsors to have a UserMetadata record"

      user_with_1.user_metadata.update!(sponsors_public_and_private_count: 1)
      user_with_2.user_metadata.update!(sponsors_public_and_private_count: 2)

      repo_by_user_with_0 = create(:repository_sponsorable, :owner, sponsorable: user_with_0).repository
      repo_by_user_with_1 = create(:repository_sponsorable, :owner, sponsorable: user_with_1).repository
      repo_by_user_with_2 = create(:repository_sponsorable, :owner, sponsorable: user_with_2).repository

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [
          repo_by_user_with_0, repo_by_user_with_2, repo_by_user_with_1,
        ].map(&:id) } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      viewer = create(:user)
      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::FEWEST_SPONSORS_SORT, per_page: 3)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)

      result = loader.paginated_sponsorables_from_dependencies

      assert_equal [user_with_0, user_with_1, user_with_2].map(&:login), result.map(&:login)
    end

    test "sorts with the maintainer with the most sponsors first when specified" do
      user_with_1 = create(:user, :sponsorable, login: "maintainer-with-1-sponsor")
      user_with_0 = create(:user, :sponsorable, login: "maintainer-without-sponsors")
      user_with_2 = create(:user, :sponsorable, login: "maintainer-with-2-sponsors")

      create(:sponsorship, sponsorable: user_with_1)
      create(:sponsorship, sponsorable: user_with_2)
      create(:sponsorship, :private, sponsorable: user_with_2)

      refute_nil user_with_1.reload_user_metadata, "expected user with 1 sponsor to have a UserMetadata record"
      refute_nil user_with_2.reload_user_metadata, "expected user with 2 sponsors to have a UserMetadata record"

      user_with_1.user_metadata.update!(sponsors_public_and_private_count: 1)
      user_with_2.user_metadata.update!(sponsors_public_and_private_count: 2)

      repo_by_user_with_0 = create(:repository_sponsorable, :owner, sponsorable: user_with_0).repository
      repo_by_user_with_1 = create(:repository_sponsorable, :owner, sponsorable: user_with_1).repository
      repo_by_user_with_2 = create(:repository_sponsorable, :owner, sponsorable: user_with_2).repository

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [
          repo_by_user_with_0, repo_by_user_with_2, repo_by_user_with_1,
        ].map(&:id) } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      viewer = create(:user)
      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT, per_page: 3)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)

      result = loader.paginated_sponsorables_from_dependencies

      assert_equal [user_with_2, user_with_1, user_with_0].map(&:login), result.map(&:login)
    end

    test "sorts with newest Sponsors profile first when specified" do
      middle_user = travel_to(1.month.ago) { create(:user, :sponsorable) }
      old_user = travel_to(1.year.ago) { create(:user, :sponsorable) }
      new_user = create(:user, :sponsorable)

      middle_user_dependency = create(:repository_sponsorable, :owner, sponsorable: middle_user).repository
      old_user_dependency = create(:repository_sponsorable, :owner, sponsorable: old_user).repository
      new_user_dependency = create(:repository_sponsorable, :owner, sponsorable: new_user).repository

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [
          middle_user_dependency, old_user_dependency, new_user_dependency,
        ].map(&:id) } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      viewer = create(:user)
      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::NEWEST_SPONSORS_PROFILE_SORT,
        per_page: 3)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)

      result = loader.paginated_sponsorables_from_dependencies

      assert_equal [new_user, middle_user, old_user], result
    end

    test "sorts with oldest Sponsors profile first when specified" do
      middle_user = travel_to(1.month.ago) { create(:user, :sponsorable) }
      old_user = travel_to(1.year.ago) { create(:user, :sponsorable) }
      new_user = create(:user, :sponsorable)

      middle_user_dependency = create(:repository_sponsorable, :owner, sponsorable: middle_user).repository
      old_user_dependency = create(:repository_sponsorable, :owner, sponsorable: old_user).repository
      new_user_dependency = create(:repository_sponsorable, :owner, sponsorable: new_user).repository

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [
          middle_user_dependency, old_user_dependency, new_user_dependency,
        ].map(&:id) } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      viewer = create(:user)
      filter_set = SponsorsExploreFilterSet.new(per_page: 3,
        sort_by: SponsorsExploreLoader::OLDEST_SPONSORS_PROFILE_SORT)
      loader = SponsorsExploreLoader.new(viewer: viewer, filter_set: filter_set)

      result = loader.paginated_sponsorables_from_dependencies

      assert_equal [old_user, middle_user, new_user], result
    end
  end

  context "#sponsoring?" do
    test "false for private sponsorship when specifying an org the viewer does not belong to" do
      sponsorable = new_sponsorable_dependency_owner
      sponsorship = create(:sponsorship, :from_org, :private, sponsorable: sponsorable)
      org = sponsorship.sponsor
      non_org_member = create(:user)
      loader = SponsorsExploreLoader.new(viewer: non_org_member, org: org)

      refute loader.sponsoring?(sponsorable.id)
    end

    test "true for private sponsorship when specifying an org the viewer belongs to" do
      sponsorable = new_sponsorable_dependency_owner
      sponsorship = create(:sponsorship, :from_org, :private, sponsorable: sponsorable)
      org = sponsorship.sponsor
      org_member = create(:user)
      org.add_member(org_member)
      loader = SponsorsExploreLoader.new(viewer: org_member, org: org)

      assert loader.sponsoring?(sponsorable.id)
    end

    test "true for private sponsorship when specifying an org the viewer admins" do
      sponsorable = new_sponsorable_dependency_owner
      sponsorship = create(:sponsorship, :from_org, :private, sponsorable: sponsorable)
      org = sponsorship.sponsor
      loader = SponsorsExploreLoader.new(viewer: org.admins.first, org: org)

      assert loader.sponsoring?(sponsorable.id)
    end

    test "true for public sponsorship when specifying an org for anonymous viewer" do
      featured_sponsorable = create(:sponsors_listing, :approved, featured_state: :active).sponsorable
      sponsorship = create(:sponsorship, :from_org, sponsorable: featured_sponsorable)
      org = sponsorship.sponsor
      loader = SponsorsExploreLoader.new(viewer: nil, org: org)

      assert loader.sponsoring?(featured_sponsorable.id)
    end

    test "true for public sponsorship when no org is specified" do
      sponsorable = new_sponsorable_dependency_owner
      sponsorship = create(:sponsorship, sponsorable: sponsorable)
      loader = SponsorsExploreLoader.new(viewer: sponsorship.sponsor)

      assert loader.sponsoring?(sponsorable.id)
    end

    test "true for private sponsorship when no org is specified" do
      sponsorable = new_sponsorable_dependency_owner
      sponsorship = create(:sponsorship, :private, sponsorable: sponsorable)
      loader = SponsorsExploreLoader.new(viewer: sponsorship.sponsor)

      assert loader.sponsoring?(sponsorable.id)
    end

    test "false for private org sponsorship when viewer is not involved in the sponsorship" do
      sponsorable = new_sponsorable_dependency_owner
      sponsorship = create(:sponsorship, :from_org, :private, sponsorable: sponsorable)
      some_rando = create(:user)
      loader = SponsorsExploreLoader.new(viewer: some_rando, org: sponsorship.sponsor)

      refute loader.sponsoring?(sponsorable.id)
    end
  end

  context "#total_sponsors" do
    test "returns count of active sponsors including private sponsors for anonymous viewer" do
      sponsors_listing = create(:sponsors_listing, :approved, :for_org, featured_state: :active)
      sponsorable = sponsors_listing.sponsorable
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: sponsorable)
      active_sponsorship1 = create(:sponsorship, sponsorable: sponsorable)
      active_sponsorship2 = create(:sponsorship, sponsorable: sponsorable)
      private_sponsorship = create(:sponsorship, :private, sponsorable: sponsorable)

      loader = SponsorsExploreLoader.new(org: sponsorable, viewer: nil)
      assert_equal 3, loader.total_sponsors(sponsorable.id), "should count private sponsorships"
    end

    test "returns count of active sponsors including private sponsors for random viewer" do
      sponsorable = create(:user, :sponsorable)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: sponsorable)
      active_sponsorship1 = create(:sponsorship, sponsorable: sponsorable)
      active_sponsorship2 = create(:sponsorship, sponsorable: sponsorable)
      private_sponsorship = create(:sponsorship, :private, sponsorable: sponsorable)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      random = create(:user)
      loader = SponsorsExploreLoader.new(viewer: random)
      assert_equal 3, loader.total_sponsors(sponsorable.id), "should count private sponsorships"
    end

    test "returns 0 when given a sponsorable ID that wasn't looked up" do
      sponsorable = create(:user, :sponsorable) # not a featured listing, doesn't own dependencies
      viewer = create(:user)
      loader = SponsorsExploreLoader.new(viewer: viewer)
      assert_equal 0, loader.total_sponsors(sponsorable.id)
    end

    test "does not count an expired one-time sponsorship" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorable = one_time_tier.sponsorable
      create(:sponsorship, :expired, sponsorable: sponsorable, tier: one_time_tier)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: sponsorable)
      assert_equal 0, loader.total_sponsors(sponsorable.id)
    end

    test "counts a recent one-time sponsorship" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorable = one_time_tier.sponsorable
      create(:sponsorship, sponsorable: sponsorable, tier: one_time_tier)
      viewer = create(:user)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: viewer)
      assert_equal 1, loader.total_sponsors(sponsorable.id)
    end

    test "counts the viewer's sponsorship" do
      sponsorship = create(:sponsorship)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorship.sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: sponsorship.sponsor)
      assert_equal 1, loader.total_sponsors(sponsorship.sponsorable_id)
    end
  end

  context "#org_sponsors" do
    test "returns count of active sponsors including private sponsors for anonymous viewer" do
      sponsors_listing = create(:sponsors_listing, :approved, :for_org, featured_state: :active)
      sponsorable = sponsors_listing.sponsorable
      inactive_sponsorship = create(:sponsorship, :from_org, :inactive, sponsorable: sponsorable)
      active_sponsorship1 = create(:sponsorship, :from_org, sponsorable: sponsorable)
      active_sponsorship2 = create(:sponsorship, :from_org, sponsorable: sponsorable)
      private_sponsorship = create(:sponsorship, :from_org, :private, sponsorable: sponsorable)

      loader = SponsorsExploreLoader.new(org: sponsorable, viewer: nil)
      assert_equal 3, loader.total_org_sponsors(sponsorable.id), "should count private sponsorships"
    end

    test "returns 0 when given a sponsorable ID that wasn't looked up" do
      sponsorable = create(:user, :sponsorable) # not a featured listing, doesn't own dependencies
      create(:sponsorship, :from_org, sponsorable: sponsorable)
      viewer = create(:user)
      loader = SponsorsExploreLoader.new(viewer: viewer)
      assert_equal 0, loader.total_org_sponsors(sponsorable.id)
    end

    test "does not count an expired one-time sponsorship" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorable = one_time_tier.sponsorable
      create(:sponsorship, :expired, :from_org, sponsorable: sponsorable, tier: one_time_tier)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: sponsorable)
      assert_equal 0, loader.total_org_sponsors(sponsorable.id)
    end
  end

  context "#first_sponsor" do
    test "does not return a sponsor for an inactive sponsorship" do
      inactive_sponsorship = create(:sponsorship, :inactive)
      viewer = create(:user)

      dependency = create(:repository_sponsorable, :owner, sponsorable: inactive_sponsorship.sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: viewer)
      assert_nil loader.first_sponsor(inactive_sponsorship.sponsorable_id)
    end

    test "does not return a sponsor for an expired one-time sponsorship" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorable = one_time_tier.sponsorable
      create(:sponsorship, :expired, sponsorable: sponsorable, tier: one_time_tier)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: sponsorable)
      assert_nil loader.first_sponsor(sponsorable.id)
    end

    test "returns one-time sponsor when the one-time payment was recent" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorable = one_time_tier.sponsorable
      sponsorship = create(:sponsorship, sponsorable: sponsorable, tier: one_time_tier)
      viewer = create(:user)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: viewer)
      assert_equal sponsorship.sponsor, loader.first_sponsor(sponsorable.id)
    end

    test "returns nil when given a sponsorable ID that wasn't looked up" do
      sponsorable = create(:user, :sponsorable) # not a featured listing, doesn't own a dependency
      viewer = create(:user)
      loader = SponsorsExploreLoader.new(viewer: viewer)

      assert_nil loader.first_sponsor(sponsorable.id)
    end

    test "returns highest-ranked sponsor for viewer" do
      shared_sponsorable = create(:user, :sponsorable)
      active_sponsorship1, active_sponsorship2 = create_pair(:sponsorship, sponsorable: shared_sponsorable)
      viewer = create(:user)

      dependency = create(:repository_sponsorable, :owner, sponsorable: shared_sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      expected_first_sponsor = active_sponsorship1.sponsor
      User.expects(:ranked_for_ids).once.returns([expected_first_sponsor.id, active_sponsorship2.sponsor_id])

      loader = SponsorsExploreLoader.new(viewer: viewer)
      assert_equal expected_first_sponsor, loader.first_sponsor(shared_sponsorable.id)
    end

    test "returns private sponsor when viewer can see them" do
      private_sponsorship = create(:sponsorship, :private, :from_org)
      org = private_sponsorship.sponsor
      sponsorable = private_sponsorship.sponsorable

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: org.admins.first)
      assert_equal org, loader.first_sponsor(sponsorable.id)
    end

    test "does not return private sponsor when viewer is the sponsor" do
      private_sponsorship = create(:sponsorship, :private)
      sponsorable = private_sponsorship.sponsorable

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: private_sponsorship.sponsor)
      assert_nil loader.first_sponsor(sponsorable.id)
    end

    test "does not return private sponsor when viewer is uninvolved in the sponsorship" do
      sponsorable = create(:user, :sponsorable)
      private_sponsorship1 = create(:sponsorship, :private, sponsorable: sponsorable)
      private_sponsorship2 = create(:sponsorship, :private, sponsorable: sponsorable)
      unrelated_user = create(:user)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: unrelated_user)
      assert_nil loader.first_sponsor(sponsorable.id)
    end

    test "returns the most relevant sponsor for the viewer" do
      sponsorable = create(:user, :sponsorable)
      active_sponsorship1 = create(:sponsorship, sponsorable: sponsorable)
      active_sponsorship2 = create(:sponsorship, sponsorable: sponsorable)

      viewer = create(:user)
      viewer.follow(active_sponsorship2.sponsor)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: viewer)
      assert_equal active_sponsorship2.sponsor, loader.first_sponsor(sponsorable.id)
    end

    test "does not return the viewer if they're the first sponsor" do
      sponsorable = create(:user, :sponsorable)
      active_sponsorship1 = create(:sponsorship, sponsorable: sponsorable)
      active_sponsorship2 = create(:sponsorship, sponsorable: sponsorable)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: active_sponsorship1.sponsor)
      assert_equal active_sponsorship2.sponsor, loader.first_sponsor(sponsorable.id)
    end

    test "returns nil if the viewer is the only sponsor" do
      sponsorship = create(:sponsorship)
      sponsorable = sponsorship.sponsorable

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: sponsorship.sponsor)
      assert_nil loader.first_sponsor(sponsorable.id)
    end

    test "returns public sponsor when viewer is logged off" do
      sponsors_listing = create(:sponsors_listing, :approved, featured_state: :active)
      sponsorable = sponsors_listing.sponsorable
      active_sponsorship = create(:sponsorship, sponsorable: sponsorable)

      loader = SponsorsExploreLoader.new(viewer: nil)
      assert_equal active_sponsorship.sponsor, loader.first_sponsor(sponsorable.id)
    end

    test "does not return private sponsor when viewer is logged off" do
      sponsorable = create(:user, :sponsorable)
      private_sponsorship = create(:sponsorship, :private, sponsorable: sponsorable)

      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = SponsorsExploreLoader.new(viewer: nil)
      assert_nil loader.first_sponsor(sponsorable.id)
    end
  end
end
