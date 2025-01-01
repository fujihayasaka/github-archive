# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "repos_public_package_boundary_test"

class RepositoriesPublicTest < Api::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository)
    @private_repo = create(:private_repository)
    @repo_deleted = create(:repository, active: false)
    @private_repo_deleted = create(:private_repository, active: false)
    @org = create :organization
    @org_owned_active = create :repository, owner: @org
    @org_owned_deleted = create :repository, owner: @org, active: false
  end

  setup do
    GitHub.packageowners.stubs(:violations_for_package_and_query).returns([])
    GitHub.stubs(:record_domain_query_violations?).returns(false)
    GitHub::SQLCheckers::DomainIsolation::TablesStatementChecker.any_instance.stubs(:in_ci?).returns(true)
    GitHub::SQLCheckers::DomainIsolation::TablesStatementChecker.any_instance.stubs(:raise_errors?).returns(true)
  end

  include Repositories::Public

  NON_REPO_ARGS = [
    [1],
    { a: 1 },
    Set.new([1]),
    Pathname.new("."),
    "1",
    1,
    nil
  ].freeze

  NON_ID_ARGS = [
    [1],
    { a: 1 },
    Set.new([1]),
    ::Repository.new,
    Pathname.new(".")
  ].freeze

  test ".find_active" do
    assert_equal @repo, find_active(@repo.id)
    assert_equal @private_repo, find_active(@private_repo.id)
    assert_nil find_active(@repo_deleted.id)
    assert_nil find_active(@private_repo_deleted.id)
    assert_nil find_active(non_existing_repo_id)
  end

  test ".find_active!" do
    assert_equal @repo, find_active!(@repo.id)
    assert_equal @private_repo, find_active!(@private_repo.id)
    assert_raises(ActiveRecord::RecordNotFound) { find_active!(@repo_deleted.id) }
    assert_raises(ActiveRecord::RecordNotFound) { find_active!(@private_repo_deleted.id) }
    assert_raises(ActiveRecord::RecordNotFound) { find_active!(non_existing_repo_id) }
  end

  test ".find_deleted" do
    assert_nil find_deleted(@repo.id)
    assert_nil find_deleted(@private_repo.id)
    assert_equal @repo_deleted, find_deleted(@repo_deleted.id)
    assert_equal @private_repo_deleted, find_deleted(@private_repo_deleted.id)
    assert_nil find_deleted(non_existing_repo_id)
  end

  test ".find_deleted!" do
    assert_raises(ActiveRecord::RecordNotFound) { find_deleted!(@repo.id) }
    assert_raises(ActiveRecord::RecordNotFound) { find_deleted!(@private_repo.id) }
    assert_equal @repo_deleted, find_deleted!(@repo_deleted.id)
    assert_equal @private_repo_deleted, find_deleted!(@private_repo_deleted.id)
    assert_raises(ActiveRecord::RecordNotFound) { find_deleted!(non_existing_repo_id) }
  end

  context ".get_active_or_deleted" do
    test "finds a repo given a valid integer or string id" do
      assert_instance_of(::Repository, get_active_or_deleted!(@repo.id))
      assert_instance_of(::Repository, get_active_or_deleted!(@repo.id.to_s))
    end

    test "raises given a nonexistent id" do
      assert_raises(ActiveRecord::RecordNotFound) do
        get_active_or_deleted!(-1)
      end
    end

    test "finds a repo given a number looking like octal and being valid octal" do
      create(:repository, id: 114117)
      assert_instance_of(::Repository, get_active_or_deleted!(114117))
      assert_instance_of(::Repository, get_active_or_deleted!("114117"))
      assert_instance_of(::Repository, get_active_or_deleted!("0114117"))
    end

    test "finds a repo given a number looking like octal but being invalid octal" do
      create(:repository, id: 114119)
      assert_instance_of(::Repository, get_active_or_deleted!(114119))
      assert_instance_of(::Repository, get_active_or_deleted!("114119"))
      assert_instance_of(::Repository, get_active_or_deleted!("0114119"))
    end
  end

  context ".load_repositories" do
    test "finds repos given a valid array of ids" do
      expected_repos = [@repo, @private_repo]
      actual_repos = load_repositories([@repo.id, @private_repo.id])

      assert_same_elements(expected_repos, actual_repos, "unexpected repos returned")
    end
  end

  context ".where_public" do
    test "finds active public repos" do
      expected_repos = [@repo]
      actual_repos = where_public([@repo.id, @repo_deleted.id, @private_repo.id, @private_repo_deleted.id])

      assert_same_elements expected_repos, actual_repos
    end
  end

  context ".organization_owned?" do
    test "returns false for user-owned repository" do
      user = create(:user)
      repo = create(:repository, owner: user)
      refute organization_owned?(repo)
    end

    test "returns true for org-owned repository" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      assert organization_owned?(repo)
    end
  end

  context ".failed_creations" do
    test "finds failed creations with failed orchestrations" do
      repo = create(:repository, :failed_creation)
      assert_equal [repo], Repositories::Public.failed_creations(1)
    end

    test "finds failed creations with abandoned orchestrations" do
      repo = create(:repository, :failed_creation)
      orchestration = CreateRepositoryOrchestration.find_by!(repository_id: repo.id)
      orchestration.update(state: :abandoned)

      assert_equal [repo], Repositories::Public.failed_creations(1)
    end

    test "finds failed creations with skipped orchestrations" do
      repo = create(:repository, :failed_creation)
      orchestration = CreateRepositoryOrchestration.find_by!(repository_id: repo.id)
      orchestration.update(state: :skipped)

      assert_equal [repo], Repositories::Public.failed_creations(1)
    end

    test "limits to query_size" do
      repo1 = create(:repository, :failed_creation)
      repo2 = create(:repository, :failed_creation)

      assert_equal 1, Repositories::Public.failed_creations(1).size
    end

    test "does not find soft deleted repos" do
      repo1 = create(:repository, :failed_creation)
      repo2 = create(:repository, :soft_deleted)

      assert_equal [repo1], Repositories::Public.failed_creations(5)
    end

    test "does not find apparent failed creations with no orchestration record" do
      repo = create(:repository)
      repo.update(active: false, deleted_at: nil)

      assert_equal [], Repositories::Public.failed_creations(5)
    end

    test "does not find failed creations with in progress orchestrations" do
      repo = create(:repository, :failed_creation)
      orchestration = CreateRepositoryOrchestration.find_by!(repository_id: repo.id)
      orchestration.update(state: :started)

      assert_equal [], Repositories::Public.failed_creations(5)
    end
  end

  context ".unsafe_is_repository?" do
    test "returns true for repos" do
      assert(unsafe_is_repository?(@repo), "expected true for @repo")
    end

    test "returns false otherwise" do
      NON_REPO_ARGS.each do |arg|
        refute(unsafe_is_repository?(arg), "expected false for non-repo #{arg.inspect}")
      end
    end
  end

  context ".filter_repo_ids_to_org" do
    test "it restricts a list of repos as described" do
      org = create(:organization)
      repo1 = create(:repository, owner: org, organization_id: org.id)
      repo2 = create(:repository, owner: org, organization_id: org.id)
      repo3 = create(:repository)
      repo4 = create(:repository, owner: org, organization_id: nil) # org owned but nil org_id
      repo5 = create(:repository, owner: org, organization_id: org.id, active: nil)
      expected_org_owned = [repo1, repo2].map(&:id)
      actual = Repositories::Public.filter_repo_ids_to_org(
        organization_id: org.id,
        repo_ids: [repo1, repo2, repo3].map(&:id)
      ).pluck(:id)
      assert_same_elements(expected_org_owned, actual, "Repositories::Public.filter_repo_ids_to_org returned the wrong list of ids")
    end
  end

  context ".accessible_repositories" do
    test "rejects repos that are not associated and not public" do
      accessible_repos = Repositories::Public.accessible_repositories(
        repository_ids: [@repo.id, @repo_deleted.id, @private_repo.id, @private_repo_deleted.id],
        associated_repository_ids: [],
      )
      assert_same_elements [@repo], accessible_repos
    end

    test "includes repos that are associated and not public" do
      accessible_repos = Repositories::Public.accessible_repositories(
        repository_ids: [@repo.id, @repo_deleted.id, @private_repo.id, @private_repo_deleted.id],
        associated_repository_ids: [@private_repo.id, @private_repo_deleted.id],
      )
      assert_same_elements [@repo, @private_repo], accessible_repos
    end

    test "includes repos that are not associated but are public" do
      accessible_repos = Repositories::Public.accessible_repositories(
        repository_ids: [@repo.id, @repo_deleted.id, @private_repo.id, @private_repo_deleted.id],
        associated_repository_ids: [],
      )
      assert_same_elements [@repo], accessible_repos
    end

    test "includes repos that are both associated and public" do
      accessible_repos = Repositories::Public.accessible_repositories(
        repository_ids: [@repo.id, @repo_deleted.id, @private_repo.id, @private_repo_deleted.id],
        associated_repository_ids: [@repo.id, @repo_deleted.id],
      )
      assert_same_elements [@repo], accessible_repos
    end
  end

  context ".finder_for" do
    test "returns a finder" do
      owner = build(:user)
      viewer = build(:user)
      permission = Platform::Authorization::Permission.new(viewer: owner, origin: Platform::ORIGIN_INTERNAL)
      repo_type = RepositoriesFinder::REPO_TYPE_TEMPLATE
      unauthorized_viewer_organization_ids = [1]

      assert_equal RepositoriesFinder, Repositories::Public.finder_for(
        owner: owner,
        viewer: viewer,
        permission: permission,
        repo_type: repo_type,
        unauthorized_viewer_organization_ids: unauthorized_viewer_organization_ids
      ).class
    end
  end

  context "#private_active_and_maintained_by_org" do
    test "returns repos that are active and maintained by the given org" do
      repo = create(:private_repository, owner: @org)

      assert_same_elements [repo],
        Repositories::Public.private_active_and_maintained_by_org(org_id: @org.id, batch_size: 5)
    end

    test "offset works" do
      repos = [create(:private_repository, owner: @org), create(:private_repository, owner: @org)]
      min_id = repos.map(&:id).min
      expected = repos.select { |r| r.id != min_id }

      assert_same_elements expected,
        Repositories::Public.private_active_and_maintained_by_org(
          org_id: @org.id,
          batch_start_id: min_id,
          batch_size: 5
        )
    end
  end

  context ".resolve_tenant" do
    test "returns business for repo in Proxima" do
      expected_business = @repo.business

      # with tenant context
      assert_equal expected_business, Repositories::Public.resolve_tenant(id: @repo.id)

      # without tenant context
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get
      assert_nil @repo.owner
      assert_nil @repo.organization

      assert_equal expected_business, Repositories::Public.resolve_tenant(id: @repo.id)
    end
  end if TestEnv.test_in_multitenancy_mode?

  if GitHub.statement_checking_enabled?
    context "cross package query checker" do
      test "nested public interface usage does not cause a violation" do
        GitHub.packageowners.stubs(:tables_to_packages_and_levels).returns({
          "repositories" => ["packages/repositories", GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Private],
          "releases" => ["packages/releases", GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Private]
        })

        # Good: Repositories public interface calls the Releases public interface
        assert_nothing_raised do
          ::ReposPublicPackageBoundary.good_find_repo_and_published_release_count_by_id(@repo.id)
        end
      end

      test "a public interface calling a private interface causes a violation" do
        GitHub.packageowners.stubs(:tables_to_packages_and_levels).returns({
          "repositories" => ["packages/repositories", GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Private],
          "releases" => ["packages/releases", GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Private]
        })

        # Bad: Repositories public interface calls the Releases private interface
        assert_raises GitHub::SQLCheckers::DomainIsolation::DomainAccessError do
          ::ReposPublicPackageBoundary.bad_find_repo_and_published_release_count_by_id(@repo.id)
        end
      end

      context "mysql dogstats properly" do
        test "uses domain" do
          GitHub::MysqlInstrumenter.with_instrument_and_track do
            GitHub.packageowners.stubs(:tables_to_packages_and_levels).returns({
              "repositories" => ["packages/repositories", GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Private],
              "releases" => ["packages/releases", GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Private]
            })

            ::ReposPublicPackageBoundary.good_find_repo_and_published_release_count_by_id(@repo.id)

            expected_tags = [
              "catalog_service:unknown",
              "cluster:repositories",
              "connection_role:writing",
              "rpc_operation:select",
              "mysql_table:repositories",
              "package:packages/repositories",
              "uses_domain:true"
            ]
            assert_dogstats_distribution(1, "rpc.mysql.dist.time", tags: expected_tags)
          end
        end

        test "does not use domain" do
          GitHub::MysqlInstrumenter.with_instrument_and_track do
            GitHub.packageowners.stubs(:tables_to_packages_and_levels).returns({
              "releases" => ["packages/releases", GitHub::Serviceowners::Packageowners::TableVisibilityLevel::Audit]
            })

            ::ReposPublicPackageBoundary.bad_find_repo_and_published_release_count_by_id(@repo.id)

            expected_tags = [
              "catalog_service:unknown",
              "cluster:repositories",
              "connection_role:writing",
              "rpc_operation:select",
              "mysql_table:releases",
              "package:packages/releases",
              "uses_domain:false"
            ]
            assert_dogstats_distribution(1, "rpc.mysql.dist.time", tags: expected_tags)
          end
        end
      end
    end
  end

  def non_existing_repo_id
    Repository.all.pluck(:id).max + 1
  end
end
