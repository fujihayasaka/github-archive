# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoriesFinderTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user)
    @_some_other_repository = create(:repository)
    @viewer = create(:user)
    @business = create(:business)
    @org = create(:organization, business: @business, admins: [@user, @viewer])
    @internal_repository = create(:internal_repository, owner: @org, name: "internal-repository")
    @private_repository = create(:private_repository, owner: @org, name: "private-repository")
    @public_repository = create(:repository, owner: @org, name: "public-repository")
  end

  context "#filter" do
    test "works" do
      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(owner_affiliations: [:owned])

      assert_equal 1, results.length
    end

    test "works for an org" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      finder = Repositories::Public.finder_for(
        owner: org,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter
      length = if results.is_a?(RepositoriesFinder::LargeScope)
        results = finder.filter(cursor: {})
        results.count
      else
        results.length
      end

      assert_equal 1, length
    end

    test "filters locked repositories" do
      locked_repo = create(:repository, owner: @user, locked: true)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(is_locked: false, owner_affiliations: [:owned])
      assert_includes results, @repository
      refute_includes results, locked_repo

      results = finder.filter(is_locked: true, owner_affiliations: [:owned])
      refute_includes results, @repository
      assert_includes results, locked_repo
    end

    test "filters forked repositories" do
      other_repo = create(:repository)
      forked_repo = create(:fork_repository, forker: @user, fork_repo: other_repo)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(is_fork: false, owner_affiliations: [:owned])
      assert_includes results, @repository
      refute_includes results, forked_repo

      results = finder.filter(is_fork: true, owner_affiliations: [:owned])
      refute_includes results, @repository
      assert_includes results, forked_repo
    end

    test "filters archived repositories" do
      archived_repo = create(:archived_repository, owner: @user)
      not_archived_repo = create(:repository, owner: @user)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(is_archived: false, owner_affiliations: [:owned])
      assert_includes results, not_archived_repo
      refute_includes results, archived_repo

      results = finder.filter(is_archived: true, owner_affiliations: [:owned])
      refute_includes results, not_archived_repo
      assert_includes results, archived_repo
    end

    test "filters by owner affiliations" do
      other_repo = create(:repository)
      other_repo.add_member(@user)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(owner_affiliations: [:owned])
      assert_includes results, @repository
      refute_includes results, other_repo

      results = finder.filter(owner_affiliations: [:direct])
      refute_includes results, @repository
      assert_includes results, other_repo
    end

    if GitHub.sponsors_enabled?
      test "filters by sponsorable only" do
        sponsorable = create(:user, :sponsorable)
        topic = create(:topic)

        # Public repo with topic but without sponsorable owner:
        create(:repository_topic, repository: @repository, topic: topic)

        # Public repo with sponsorable owner but without topic:
        create(:repository_sponsorable, :owner, sponsorable: sponsorable)

        # Public repo with topic and sponsorable owner:
        pub_repo_with_topic = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
        create(:repository_topic, repository: pub_repo_with_topic, topic: topic)

        # Private repo with topic and sponsorable owner:
        private_repo = create(:private_repository, owner: sponsorable)
        create(:repository_sponsorable, :owner, sponsorable: sponsorable, repository: private_repo)
        create(:repository_topic, repository: private_repo, topic: topic)

        finder = Repositories::Public.finder_for(
          owner: topic,
          viewer: @viewer,
          permission: build_permission,
          unauthorized_viewer_organization_ids: [],
        )

        results = finder.filter(
          sponsorable_only: true,
          owner_affiliations: [:owned, :direct],
          affiliations: [:owned, :direct],
        )

        assert_equal 1, results.size
        assert_equal pub_repo_with_topic.name, results.first.name
      end
    end

    test "respects unauthorized_viewer_organization_ids" do
      org = create(:organization)
      unauthorized_repo = create(:repository, owner: org)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [org.id],
      )

      results = finder.filter(owner_affiliations: [:owned])
      refute_includes results, unauthorized_repo
    end

    test "filters by type" do
      private_repo = create(:private_repository, owner: @user)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(type: "public", owner_affiliations: [:owned])
      assert_includes results, @repository
      refute_includes results, private_repo

      # viewer is not a member of the repo yet
      results = finder.filter(type: "private", owner_affiliations: [:owned])
      refute_includes results, @repository
      refute_includes results, private_repo

      private_repo.add_member(@viewer)
      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
              )

      # viewer now has visibility of the private repo
      results = finder.filter(type: "private", owner_affiliations: [:owned])
      refute_includes results, @repository
      assert_includes results, private_repo
    end

    test "filters to repositories with a sponsorable owner when type=sponsorable" do
      sponsorable_repo = create(:repository_sponsorable, :owner).repository
      sponsorable = sponsorable_repo.owner
      finder = Repositories::Public.finder_for(
        owner: sponsorable,
        viewer: sponsorable,
        permission: Platform::Authorization::Permission.new(viewer: sponsorable, origin: Platform::ORIGIN_INTERNAL),
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(type: "sponsorable", owner_affiliations: [:owned])

      assert_equal [sponsorable_repo], results
    end if GitHub.sponsors_enabled?

    test "filters by privacy" do
      private_repo = create(:private_repository, owner: @user)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
              )

      results = finder.filter(privacy: "public", owner_affiliations: [:owned])
      assert_includes results, @repository
      refute_includes results, private_repo

      # viewer is not a member of the repo yet
      results = finder.filter(privacy: "private", owner_affiliations: [:owned])
      refute_includes results, @repository
      refute_includes results, private_repo

      private_repo.add_member(@viewer)
      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      # viewer now has visibility of the private repo
      results = finder.filter(privacy: "private", owner_affiliations: [:owned])
      refute_includes results, @repository
      assert_includes results, private_repo
    end

    test "filters by all visibility if not provided" do
      finder = Repositories::Public.finder_for(
        owner: @org,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      # ensure that we're starting with the correct set of repositories
      results = finder.filter
      results = results.scope if results.is_a?(RepositoriesFinder::LargeScope)
      assert_same_elements [@public_repository, @private_repository, @internal_repository], results
    end

    test "filters by private visibility" do
      finder = Repositories::Public.finder_for(
        owner: @org,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      # ensure that only private repos are returned when visibility is private
      private_results = finder.filter(visibility: "private")
      private_results = private_results.scope if private_results.is_a?(RepositoriesFinder::LargeScope)
      assert_same_elements [@private_repository], private_results
    end

    test "filters by public visibility" do
      finder = Repositories::Public.finder_for(
        owner: @org,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      # ensure that only public repos are returned when visibility is public
      public_results = finder.filter(visibility: "public")
      public_results = public_results.scope if public_results.is_a?(RepositoriesFinder::LargeScope)
      assert_same_elements [@public_repository], public_results
    end

    test "filters by internal visibility" do
      finder = Repositories::Public.finder_for(
        owner: @org,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      # ensure that only internal repos are returned when visibility is internal
      internal_results = finder.filter(visibility: "internal")
      internal_results = internal_results.scope if internal_results.is_a?(RepositoriesFinder::LargeScope)
      assert_same_elements [@internal_repository], internal_results
    end

    test "respects order_by" do
      old_repo = create(:repository, owner: @user, created_at: 100.years.ago)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(order_by: { field: "created_at", direction: "desc" }, owner_affiliations: [:owned])
      assert_equal [@repository.id, old_repo.id], results.map(&:id)

      results = finder.filter(order_by: { field: "created_at", direction: "asc" }, owner_affiliations: [:owned])
      assert_equal [old_repo.id, @repository.id], results.map(&:id)
    end

    test "respects order_by when specified with symbols instead of strings" do
      old_repo = create(:repository, owner: @user, created_at: 100.years.ago)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      results = finder.filter(order_by: { field: :created_at, direction: :desc }, owner_affiliations: [:owned])
      assert_equal [@repository.id, old_repo.id], results.map(&:id)

      results = finder.filter(order_by: { field: :created_at, direction: :asc }, owner_affiliations: [:owned])
      assert_equal [old_repo.id, @repository.id], results.map(&:id)
    end

    test "sorts by default if order_by not provided" do
      Flipper[:repositories_finder_default_order].enable

      repo1 = create(:repository, owner: @user)
      repo2 = create(:repository, owner: @user)
      repo3 = create(:repository, owner: @user)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      default_results = finder.filter(owner_affiliations: [:owned])

      assert_equal [@repository, repo1, repo2, repo3], default_results

      repo1.update_pushed_at(1.day.ago)
      repo2.update_pushed_at(5.days.ago)
      repo3.update_pushed_at(3.days.ago)

      ordered_results = finder.filter(order_by: { field: "pushed_at", direction: "desc" }, owner_affiliations: [:owned])

      assert_equal [@repository, repo1, repo3, repo2], ordered_results
    end

    test "does not allow order to inject sql" do
      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
      )

      assert_nothing_raised do
        finder.filter(order_by: { field: "created_at; SELECT * from users;", direction: "desc; SELECT * from users;" }, owner_affiliations: [:owned])
      end
    end

    context "disabled repos" do
      test "filters when asked" do
        admin = create(:user)
        org = create(:organization, admin: admin)
        disabled_repo = create(:repository, owner: org)
        disabled_repo.update_attribute :disabled_at, Time.now
        disabled_repo.update_attribute :disabling_reason, "dmca"

        finder = Repositories::Public.finder_for(
          owner: org,
          viewer: admin,
          permission: build_permission,
          unauthorized_viewer_organization_ids: [],
        )

        refute_includes finder.filter, disabled_repo
      end

      test "does not filter when asked" do
        admin = create(:user)
        org = create(:organization, admin: admin)
        disabled_repo = create(:repository, owner: org)
        disabled_repo.update_attribute :disabled_at, Time.now
        disabled_repo.update_attribute :disabling_reason, "dmca"

        finder = Repositories::Public.finder_for(
          owner: org,
          viewer: admin,
          permission: build_permission,
          unauthorized_viewer_organization_ids: [],
        )

        assert_includes finder.filter(filter_spam: false), disabled_repo
      end
    end
  end

  context "watched repositories" do
    test "returns watched repositories" do
      @user.watch_repo(@repository)
      unwatched_repo = create(:repository, owner: @user)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
        repo_type: RepositoriesFinder::REPO_TYPE_WATCHED
      )

      results = finder.filter(order_by: { field: "created_at", direction: "desc" }, owner_affiliations: [:owned])
      assert_includes results, @repository
      refute_includes results, unwatched_repo
    end
  end

  context "template repositories" do
    test "returns template repositories" do
      template_repo = create(:repository, template: true, owner: @user)

      finder = Repositories::Public.finder_for(
        owner: @user,
        viewer: @viewer,
        permission: build_permission,
        unauthorized_viewer_organization_ids: [],
        repo_type: RepositoriesFinder::REPO_TYPE_TEMPLATE
      )

      results = finder.filter(order_by: { field: "created_at", direction: "desc" }, owner_affiliations: [:owned])
      refute_includes results, @repository
      assert_includes results, template_repo
    end
  end

  def build_permission
    @_permission ||= Platform::Authorization::Permission.new(
      viewer: @viewer,
      origin: Platform::ORIGIN_INTERNAL
    )
  end
end
