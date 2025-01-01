# typed: true
# frozen_string_literal: true

require "test_helper"

class ByOrgMemberTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @user = create(:user)
    @org = create :organization, admin: @user
    create :private_repository, name: "h", owner: @org
    create :private_repository, name: "b", owner: @org
    create :private_repository, name: "z", owner: @org
    @pub_repo = create :repository, name: "a", owner: @org
    create :repository, name: "f", owner: @org
  end

  setup do
    act_as(@user)
    @domain = T.let(Repositories::Domain.new, T.nilable(Repositories::Domain))
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  sig { returns(Repositories::Domain) }
  def domain
    T.must(@domain)
  end

  def call_domain(organization = @org, **kwargs)
    args = Repositories::ByOrgMemberArgs.new(
      T.unsafe(
        organization: organization,
        user: @user,
        pagination: GH::Pagination::Cursor.new(first: 1, disable_auth: true),
        permission: Repositories::PlatformPermissionSwitch.new(
          Platform::Authorization::Permission.new(viewer: @user, origin: Platform::ORIGIN_API)
        ),
        with_members: true,
        with_page_info: true,
        with_total_count: true,
        with_total_disk_usage: true,
        **kwargs
      )
    )
    T.cast(domain.by_org_member(args), GH::Domain::CursorCollection[Repositories::IRepository])
  end

  test "no filters" do
    repos = call_domain

    assert_equal 5, repos.total_entries
    assert_equal @org.repositories.order(:id).limit(1).pluck(:id), repos.map(&:id)
    assert repos.has_next_page?
  end

  test "visibility" do
    enterprise_org = create :enterprise_linked_organization
    create :internal_repository, name: "r", owner: enterprise_org
    create :repository, name: "f", owner: enterprise_org

    repos = call_domain(enterprise_org, visibility: Repositories::RepositoryVisibility::Internal)

    assert_equal 1, repos.total_entries
    assert_equal enterprise_org.repositories.private_scope.order(:id).limit(1).pluck(:id), repos.map(&:id)
    refute repos.has_next_page?
  end

  test "privacy" do
    repos = call_domain(visibility: Repositories::RepositoryVisibility::Private)

    assert_equal 3, repos.total_entries
    assert_equal @org.repositories.private_scope.order(:id).limit(1).pluck(:id), repos.map(&:id)
    assert repos.has_next_page?
  end

  test "is_fork" do
    forker = create(:user)
    @org.add_member(forker)
    fork_repo = create(:fork_repository, forker: forker, fork_repo: @pub_repo, organization: @org)

    repos = call_domain(is_fork: true)

    assert_equal 1, repos.total_entries
    assert_equal @org.repositories.forks.order(:id).limit(1).pluck(:id), repos.map(&:id)
    refute repos.has_next_page?
  end

  test "is_locked" do
    locked_repo = create(:repository, owner: @org, locked: true)

    repos = call_domain(is_locked: true)

    assert_equal 1, repos.total_entries
    assert_equal @org.repositories.locked_repos.order(:id).limit(1).pluck(:id), repos.map(&:id)
    refute repos.has_next_page?
  end

  context "type" do
    test "Public" do
      repos = call_domain(type: Repositories::RepositoryType::Public)

      assert_equal 2, repos.total_entries
      assert_equal @org.repositories.public_scope.order(:id).limit(1).pluck(:id), repos.map(&:id)
      assert repos.has_next_page?
    end

    test "Private" do
      repos = call_domain(type: Repositories::RepositoryType::Private)

      assert_equal 3, repos.total_entries
      assert_equal @org.repositories.private_scope.order(:id).limit(1).pluck(:id), repos.map(&:id)
      assert repos.has_next_page?
    end

    test "Fork" do
      forker = create(:user)
      @org.add_member(forker)
      fork_repo = create(:fork_repository, forker: forker, fork_repo: @pub_repo, organization: @org)

      repos = call_domain(type: Repositories::RepositoryType::Fork)

      assert_equal 1, repos.total_entries
      assert_equal @org.repositories.forks.order(:id).limit(1).pluck(:id), repos.map(&:id)
      refute repos.has_next_page?
    end

    if GitHub.mirrors_enabled?
      test "Mirror" do
        mirror = create(:mirror_repository, owner: @org)

        repos = call_domain(type: Repositories::RepositoryType::Mirror)

        assert_equal 1, repos.total_entries
        assert_equal [mirror.id], repos.map(&:id)
        refute repos.has_next_page?
      end
    end

    test "Template" do
      template = create(:repository, template: true, owner: @org)#, from_example: :simple)

      repos = call_domain(type: Repositories::RepositoryType::Template)

      assert_equal 1, repos.total_entries
      assert_equal [template.id], repos.map(&:id)
      refute repos.has_next_page?
    end

    test "Archived" do
      archived = create(:archived_repository, owner: @org)

      repos = call_domain(type: Repositories::RepositoryType::Archived)

      assert_equal 1, repos.total_entries
      assert_equal [archived.id], repos.map(&:id)
      refute repos.has_next_page?
    end

    if GitHub.sponsors_enabled?
      test "Sponsorable" do
        sponsorable_org = create(:organization, :sponsorable)
        sponsored_repository = create(:repository, owner: sponsorable_org)
        create(:repository_sponsorable, :owner, sponsorable: sponsorable_org, repository: sponsored_repository)
        create(:repository, owner: sponsorable_org)

        repos = call_domain(sponsorable_org, type: Repositories::RepositoryType::Sponsorable)

        assert_equal 1, repos.total_entries
        assert_equal [sponsored_repository.id], repos.map(&:id)
        refute repos.has_next_page?
      end
    end
  end

  test "fails if bad actor gate is enabled" do
    domain_method_actor = Repositories::Domain::BadActorGate::DomainMethodActor.new(
      T.must(Repositories::Domain.name),
      :by_org_member,
      @user.id,
      @org.id
    )
    enable_feature_flag(:repos_domain_bad_actor_gate, domain_method_actor)

    assert_raises(Repositories::Domain::BadActorGate::Error::UnprocessableEntity) do
      call_domain
    end

    disable_feature_flag(:repos_domain_bad_actor_gate)

    repos = call_domain

    assert_equal 5, repos.total_entries
  end
end
