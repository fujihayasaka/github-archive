# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryDomainTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @user = create(:user)
    @other_user = create(:user)
    @staff_admin_user = create(:staff_admin_user)
    @spammer = create(:user, spammy: true)
    @admin = create(:user)
    @org1 = create(:organization, admin: @admin)
    @org2 = create(:organization, admin: @admin)
    @business = create(:business)
    @business_org = create(:enterprise_linked_organization, business: @business)
    @other_org = create(:enterprise_linked_organization)

    @internal_repo = create(:internal_repository, owner: @business_org)
    @internal_deleted_repo = create(:internal_repository, owner: @business_org)
    @internal_deleted_repo.remove(@business_org.admins.first)
    @other_org_internal_repo = create(:internal_repository, owner: @other_org)

    @repo = create(:repository, owner: @user)
    @repo.redirect_from_previous_location("#{@other_user.login}/old-repo")
    @org_repo1 = create(:repository, owner: @org1)
    @org_repo2 = create(:repository, owner: @org2)

    @disabled_repo = create(:repository)
    @disabled_repo.access.disable("size", @staff_admin_user)
    @spammy_repo = create(:repository, owner: @spammer)
  end

  setup do
    @domain = T.let(Repositories::Domain.new, T.nilable(Repositories::Domain))
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  sig { returns(Repositories::Domain) }
  def domain
    T.must(@domain)
  end

  context "#by_qualified_name" do
    test "finds repos by their nwo" do
      assert_equal @repo, domain.by_qualified_name("#{@repo.owner.login}/#{@repo.name}")
    end

    test "finds redirected repos when search_redirects is true" do
      assert_equal @repo, domain.by_qualified_name("#{@other_user.login}/old-repo", search_redirects: true)
    end

    test "does not find redirected repos search_redirects is false" do
      assert_nil domain.by_qualified_name("#{@other_user.login}/old-repo", search_redirects: false)
    end

    test "returns nil for non 3 byte UTF-8" do
      assert_no_query_warnings do
        assert_query_count 0, ignore_feature_flags: true do
          assert_nil domain.by_qualified_name("#{@repo.owner_display_login}/emoji-🎃")
        end
      end
    end

    test "returns nil for non 3 byte UTF-8 owner" do
      assert_no_query_warnings do
        assert_query_count 0, ignore_feature_flags: true do
          assert_nil domain.by_qualified_name("emoji-🎃/#{@repo.name}")
        end
      end
    end

    test "finds correct repository based on owner display login in multi-tenant mode" do
      on_multi_tenant_enterprise do
        user = create(:emu, login: "mtodd")
        business = user.enterprise_managed_business
        shortcode = business.shortcode
        repo = create(:repository, owner: user)
        repo.redirect_from_previous_location("mtodd_#{shortcode}/old-repo")

        GitHub::CurrentTenant.remove

        assert_nil domain.by_qualified_name(repo.name)
        assert_nil domain.by_qualified_name("mtodd/#{repo.name}")
        assert_equal repo, domain.by_qualified_name("mtodd_#{shortcode}/#{repo.name}")

        assert_nil domain.by_qualified_name("mtodd/old-repo", search_redirects: true)
        assert_equal repo, domain.by_qualified_name("mtodd_#{shortcode}/old-repo", search_redirects: true)

        GitHub::CurrentTenant.set(business)

        assert_nil domain.by_qualified_name(repo.name)
        assert_equal repo, domain.by_qualified_name("mtodd/#{repo.name}")
        assert_equal repo, domain.by_qualified_name("mtodd_#{shortcode}/#{repo.name}")
        assert_nil domain.by_qualified_name("mtodd_othertenant/#{repo.name}")

        assert_equal repo, domain.by_qualified_name("mtodd/old-repo", search_redirects: true)
        assert_equal repo, domain.by_qualified_name("mtodd_#{shortcode}/old-repo", search_redirects: true)
      end
    end
  end

  context "#by_org_member" do
    test "finds repos by org and user" do
      user = create(:user)
      organization = create(:organization, admin: user)
      repo = create(:repository, owner: organization)
      create(:repository, owner: user)

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 5)
      args = Repositories::ByOrgMemberArgs.new(
        organization: organization,
        user: user,
        pagination:,
        permission: Repositories::PlatformPermissionSwitch.new(nil, override: true),
        filter_spam: false
      )
      repos = domain.by_org_member(args)

      assert_same_elements([repo.id], repos.map(&:id))
    end

    test "pagination" do
      user = create(:user)
      organization = create(:organization, admin: user)
      2.times { create(:repository, owner: organization) }

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 1)
      args = Repositories::ByOrgMemberArgs.new(
        organization: organization,
        user: user,
        pagination:,
        permission: Repositories::PlatformPermissionSwitch.new(nil, override: true),
        filter_spam: false
      )
      repos = domain.by_org_member(args)
      assert_same_elements(organization.repositories.order(:id).limit(1).pluck(:id), repos.map(&:id))

      pagination = GH::Pagination::Offset.new(page: 2, per_page: 1)
      args = Repositories::ByOrgMemberArgs.new(
        organization: organization,
        user: user,
        pagination:,
        permission: Repositories::PlatformPermissionSwitch.new(nil, override: true),
        filter_spam: false
      )
      repos = domain.by_org_member(args)
      assert_same_elements(organization.repositories.order(:id).limit(1).offset(1).pluck(:id), repos.map(&:id))
    end

    test "cursor pagination" do
      user = create(:user)
      organization = create(:organization, admin: user)
      2.times { create(:repository, owner: organization) }

      after_repo = organization.repositories.order(:id).limit(1).pluck(:id)
      cursor = Platform::ConnectionWrappers::CursorGenerator.generate_cursor(after_repo, version: :v2)
      pagination = GH::Pagination::Cursor.new(first: 1, after: cursor, disable_auth: true)
      args = Repositories::ByOrgMemberArgs.new(
        organization: organization,
        user: user,
        pagination:,
        permission: Repositories::PlatformPermissionSwitch.new(nil, override: true),
        filter_spam: false,
        with_members: true,
      )
      repos = domain.by_org_member(args)

      expected_repo_ids = organization.repositories.order(:id).where("id > ?", after_repo.first).limit(1).pluck(:id)
      assert_same_elements(expected_repo_ids, repos.map(&:id))
    end

    test "sorting" do
      user = create(:user)
      organization = create(:organization, admin: user)
      create(:repository, owner: organization, name: "aaa")
      create(:repository, owner: organization, name: "zzz")

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 5)
      args = Repositories::ByOrgMemberArgs.new(
        organization: organization,
        user: user,
        pagination:,
        permission: Repositories::PlatformPermissionSwitch.new(nil, override: true),
        filter_spam: false,
        sort: Repositories::SortBy::FullName,
        direction: GH::Pagination::Sort::Direction::DESC,
      )
      repos = domain.by_org_member(args)

      assert_same_elements(organization.repositories.order("name DESC").pluck(:id), repos.map(&:id))
    end

    test "public_only" do
      user = create(:user)
      organization = create(:organization, admin: user)
      create(:private_repository, owner: organization)
      repo = create(:repository, owner: organization)

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 5)
      args = Repositories::ByOrgMemberArgs.new(
        organization: organization,
        user: user,
        pagination:,
        permission: Repositories::PlatformPermissionSwitch.new(nil, override: true),
        privacy: Repositories::RepositoryVisibility::Public,
        filter_spam: false
      )
      repos = domain.by_org_member(args)

      assert_same_elements([repo.id], repos.map(&:id))
    end
  end

  context "#by_org_excluding" do
    test "finds repos by org and excluded repo ids" do
      organization = create(:organization)
      repo1 = create(:repository, owner: organization)
      repo2 = create(:repository, owner: organization)
      repo3 = create(:repository, owner: organization)
      repo4 = create(:private_repository, owner: organization)

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 5)
      repos = T.cast(
        domain.by_org_excluding(
          organization_id: organization.id,
          excluded_repo_ids: [],
          pagination:,
          max_pages: 5
        ),
        GH::Domain::OffsetCollection[Repositories::IRepository]
      )

      assert_same_elements([repo1.id, repo2.id, repo3.id], repos.map(&:id))
      assert_equal 4, repos.total_entries

      repos = T.cast(
        domain.by_org_excluding(
          organization_id: organization.id,
          excluded_repo_ids: [repo1],
          pagination:,
          max_pages: 5
        ),
        GH::Domain::OffsetCollection[Repositories::IRepository]
      )

      assert_same_elements([repo2.id, repo3.id], repos.map(&:id))
      assert_equal 4, repos.total_entries

      repos = T.cast(
        domain.by_org_excluding(
          organization_id: organization.id,
          excluded_repo_ids: [repo1],
          pagination:,
          max_pages: 5,
          public_only: false
        ),
        GH::Domain::OffsetCollection[Repositories::IRepository]
      )

      assert_same_elements([repo2.id, repo3.id, repo4.id], repos.map(&:id))
      assert_equal 4, repos.total_entries
    end

    test "pagination" do
      organization = create(:organization)
      repo1 = create(:repository, owner: organization)
      repo2 = create(:repository, owner: organization)
      repo3 = create(:repository, owner: organization)

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 1)
      repos = T.cast(
        domain.by_org_excluding(
          organization_id: organization.id,
          excluded_repo_ids: [],
          pagination:,
          max_pages: 5
        ),
        GH::Domain::OffsetCollection[Repositories::IRepository]
      )

      assert_same_elements([repo1.id], repos.map(&:id))
      assert_equal 3, repos.total_entries

      pagination = GH::Pagination::Offset.new(page: 2, per_page: 1)
      repos = T.cast(
        domain.by_org_excluding(
          organization_id: organization.id,
          excluded_repo_ids: [],
          pagination:,
          max_pages: 2
        ),
        GH::Domain::OffsetCollection[Repositories::IRepository]
      )
      assert_same_elements([repo2.id], repos.map(&:id))
      assert_equal 2, repos.total_entries
    end
  end

  context "#active_by_id" do
    test "finds requested repo by its id" do
      repo = T.must(domain.active_by_id(@repo.id))
      assert_equal @repo.id, repo.id
      assert_equal @repo.name, repo.name
    end

    test "returns nil for deleted repos" do
      deleted_repo = create(:deleted_repository)
      assert_nil domain.active_by_id(deleted_repo.id)
    end
  end

  context "#by_id" do
    test "finds requested repo by its id" do
      repo = T.must(domain.by_id(@repo.id))
      assert_equal @repo.id, repo.id
      assert_equal @repo.name, repo.name
    end

    test "returns deleted repos" do
      deleted_repo = create(:deleted_repository)
      repo = T.must(domain.by_id(deleted_repo.id))
      assert_equal deleted_repo.id, repo.id
      assert_equal deleted_repo.name, repo.name
    end
  end

  context "#repo_ids_by_org_ids" do
    test "finds requested repo ids by org ids" do
      assert_equal [@org_repo1.id, @org_repo2.id], domain.repo_ids_by_org_ids(org_ids: [@org1.id, @org2.id])
    end

    test "requires a single query when less than max_rows" do
      domain.stubs(:max_rows).returns(10)
      assert_query_count(1) do
        assert_equal [@org_repo1.id, @org_repo2.id], domain.repo_ids_by_org_ids(org_ids: [@org1.id, @org2.id])
      end
    end

    test "requires a (1 + records / max_rows) queries when more than max_rows" do
      domain.stubs(:max_rows).returns(1)

      assert_query_count(3) do
        assert_equal [@org_repo1.id, @org_repo2.id], domain.repo_ids_by_org_ids(org_ids: [@org1.id, @org2.id])
      end
    end

    test "finds requested repo ids for an org exceeding max_rows" do
      domain.stubs(:max_rows).returns(1)

      repo = create(:repository, owner: @org1)

      assert_equal [@org_repo1.id, repo.id, @org_repo2.id], domain.repo_ids_by_org_ids(org_ids: [@org1.id, @org2.id])
    end
  end

  context "#internal_repo_ids_by_business_ids" do
    test "finds internal repo ids by business ids" do
      ids = domain.internal_repo_ids_by_business_ids(business_ids: [@business.id], active_only: false)

      if GitHub.enterprise?
        # On an enterprise, only a single business can exist, so any internal repo in that business is included
        assert_same_elements [@internal_repo.id, @internal_deleted_repo.id, @other_org_internal_repo.id], ids
      else
        assert_same_elements [@internal_repo.id, @internal_deleted_repo.id], ids
      end
    end

    test "excludes non-internal repo ids by business ids" do
      create(:private_repository, owner: @business_org)
      create(:public_repository, owner: @business_org)

      ids = domain.internal_repo_ids_by_business_ids(business_ids: [@business.id], active_only: false)

      if GitHub.enterprise?
        # On an enterprise, only a single business can exist, so any internal repo in that business is included
        assert_same_elements [@internal_repo.id, @internal_deleted_repo.id, @other_org_internal_repo.id], ids
      else
        assert_same_elements [@internal_repo.id, @internal_deleted_repo.id], ids
      end
    end

    test "finds internal repo ids by business ids with active_only" do
      ids = domain.internal_repo_ids_by_business_ids(business_ids: [@business.id], active_only: true)

      if GitHub.enterprise?
        # On an enterprise, only a single business can exist, so any internal repo in that business is included
        assert_same_elements [@internal_repo.id, @other_org_internal_repo.id], ids
      else
        assert_same_elements [@internal_repo.id], ids
      end
    end

    test "finds internal repo ids by business ids for multiple businesses", skip_enterprise: true do
      ids = domain.internal_repo_ids_by_business_ids(business_ids: [@business.id, @other_org.business.id], active_only: false)

      assert_same_elements [@internal_repo.id, @internal_deleted_repo.id, @other_org_internal_repo.id], ids
    end

    test "finds internal repo ids by business ids for a business with more than max_rows internal repos" do
      domain.stubs(:max_internal_repository_batch_size).returns(1)

      ids = domain.internal_repo_ids_by_business_ids(business_ids: [@business.id], active_only: false)

      if GitHub.enterprise?
        # On an enterprise, only a single business can exist, so any internal repo in that business is included
        assert_same_elements [@internal_repo.id, @internal_deleted_repo.id, @other_org_internal_repo.id], ids
      else
        assert_same_elements [@internal_repo.id, @internal_deleted_repo.id], ids
      end
    end
  end

  context "#repo_ids_by_owners" do
    test "finds requested repo ids by owner ids" do
      ids = domain.repo_ids_by_owners(owner_ids: [@user.id, @org1.id])
      assert_same_elements [@repo.id, @org_repo1.id], ids
    end

    test "finds requested repo ids by owner ids in batches" do
      domain.stubs(:max_rows).returns(1)

      ids = domain.repo_ids_by_owners(owner_ids: [@user.id, @org1.id])
      assert_same_elements [@repo.id, @org_repo1.id], ids
    end

    test "finds requested repo ids by owner ids with include_repo_ids" do
      ids = domain.repo_ids_by_owners(owner_ids: [@user.id, @org1.id], include_repo_ids: [@org_repo1.id])
      assert_same_elements [@org_repo1.id], ids
    end

    test "finds requested repo ids by owner ids with exclude_repo_ids" do
      ids = domain.repo_ids_by_owners(owner_ids: [@user.id, @org1.id], exclude_repo_ids: [@org_repo1.id])
      assert_same_elements [@repo.id], ids
    end

    test "finds requested repo ids by owner ids with archived_only" do
      @repo.update!(archived_at: Time.now)
      ids = domain.repo_ids_by_owners(owner_ids: [@user.id, @org1.id], archived_only: true)
      assert_same_elements [@repo.id], ids
    end

    test "finds requested repo ids by owner ids with exclude_archived" do
      @repo.update!(archived_at: Time.now)
      ids = domain.repo_ids_by_owners(owner_ids: [@user.id, @org1.id], exclude_archived: true)
      assert_same_elements [@org_repo1.id], ids
    end

    test "yields requested repo ids in batches when block is passed" do
      domain.stubs(:max_rows).returns(2)

      ids = []
      iteration_count = 0
      domain.repo_ids_by_owners(owner_ids: [@user.id, @org1.id, @org2.id]) do |id_batch|
        iteration_count += 1
        ids.concat(id_batch)
        assert id_batch.size <= 2
      end

      assert_equal 2, iteration_count
      assert_same_elements [@repo.id, @org_repo1.id, @org_repo2.id], ids
    end

    test "raises error when mutually exclusive options are used" do
      assert_raises(Repositories::Domain::Error::UnprocessableError) do
        domain.repo_ids_by_owners(owner_ids: [@user.id], archived_only: true, exclude_archived: true)
      end
    end

    context "#filter_spam_from_repo_ids" do
      test "filters disabled repos if exclude_disabled_repos" do
        assert_equal [], domain.filter_spam_from_repo_ids(current_user: @user, repo_ids: [@disabled_repo], exclude_disabled_repos: true)
      end

      test "includes disabled repos if not exclude_disabled_repos" do
        assert_equal [@disabled_repo.id], domain.filter_spam_from_repo_ids(current_user: @user, repo_ids: [@disabled_repo], exclude_disabled_repos: false)
      end

      if GitHub.spamminess_check_enabled?
        test "filters spam repos if the viewer is not staff or the spammer" do
          assert_equal [], domain.filter_spam_from_repo_ids(current_user: @user, repo_ids: [@spammy_repo], exclude_disabled_repos: true)
        end

        test "keeps spam repos if the viewer is the spammer" do
          assert_equal [@spammy_repo.id], domain.filter_spam_from_repo_ids(current_user: @spammer, repo_ids: [@spammy_repo], exclude_disabled_repos: true)
        end

        test "keeps spam repos if the viewer is a staff admin" do
          assert_equal [@spammy_repo.id], domain.filter_spam_from_repo_ids(current_user: @staff_admin_user, repo_ids: [@spammy_repo], exclude_disabled_repos: true)
        end
      end

      test "keeps non-spam, non-disabled repos for random viewer" do
        assert_equal [@repo.id], domain.filter_spam_from_repo_ids(current_user: @user, repo_ids: [@repo], exclude_disabled_repos: true)
      end

      test "keeps non-spam, non-disabled repos for anonymous viewer" do
        assert_equal [@repo.id], domain.filter_spam_from_repo_ids(current_user: nil, repo_ids: [@repo], exclude_disabled_repos: true)
      end

      test "filters keeps non-spam, disabled repos for anonymous viewer when exclude_disabled_repos" do
        assert_equal [], domain.filter_spam_from_repo_ids(current_user: nil, repo_ids: [@disabled_repo], exclude_disabled_repos: true)
      end
    end
  end

  class TestUsage
    include Repositories::Domain::Provider

    def get_repo(nwo)
      repositories_domain.by_qualified_name(nwo)
    end
  end

  context "#by_ids" do
    test "finds requested repos by their ids" do
      second_repo = create(:repository)
      repos = domain.by_ids([@repo.id, second_repo.id])
      assert_equal [@repo.id, second_repo.id].sort, repos.map(&:id).sort
    end

    test "does not return deleted repos by default" do
      deleted_repo = create(:deleted_repository)
      assert_equal domain.by_ids([deleted_repo.id]).map(&:id), []
    end

    test "optionally includes deleted repos" do
      deleted_repo = create(:deleted_repository)
      repos = domain.by_ids([deleted_repo.id], allow_deleted: true)
      assert_equal repos.map(&:id), [deleted_repo.id]
    end
  end

  context "#update_stargazer_count" do
    test "updates the stargazer_count field if the given value differs from the existing value" do
      repo = create(:repository, stargazer_count: 0)

      assert domain.update_stargazer_count(repository_id: repo.id, count: 1)
      assert_equal 1, repo.reload.stargazer_count

      Repository.any_instance.expects(:update_attribute).never
      assert domain.update_stargazer_count(repository_id: repo.id, count: 1)
      assert_equal 1, repo.reload.stargazer_count
    end

    test "returns false when repo not found" do
      refute domain.update_stargazer_count(repository_id: 999_999, count: 1)
    end
  end

  context "provider" do
    test "a provider is created and returns a bootstrapped domain" do
      GitHub.serviceowners&.stubs(:service_for_path)&.returns(:test)

      instance = TestUsage.new
      assert_equal instance.get_repo(@repo.nwo).id, @repo.id
    end
  end
end
