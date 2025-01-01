# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../domain_test"

class Repositories::Domain::TotalActiveCountByOwnerTest < Repositories::DomainTest

  fixtures do
    business = create(:business)
    @org_admin = create(:user, login: "org-admin")
    @org = create(:organization, admin: @org_admin, plan: "bronze", business: business)
    business.add_organization(@org)
    @org.allow_private_repository_forking(actor: @org.admin)
    repositories = create_list(:repository, 5, owner: @org)
    fork_repository = create(:fork_repository, fork_repo: repositories[4], forker: @org.admin, owner: @org)
    repositories[0].update!(active: false)
    repositories[1].toggle_visibility(actor: @org.admin, visibility: "private")
    repositories[2].lock!
    repositories[3].toggle_visibility(actor: @org.admin, visibility: "internal")
  end

  context "#total_count_by_owner" do
    test "counts all repositories" do
      assert_equal(
        @org.repositories.count,
        count_by_owner(@org)
      )
    end

    test "counts all repositories with lower limit" do
      assert_equal(
        [@org.repositories.count, 1].min,
        count_by_owner(@org, limit: 1)
      )
    end

    test "counts all repositories with higher limit" do
      assert_equal(
        [@org.repositories.count, 6].min,
        count_by_owner(@org, limit: 6)
      )
    end

    test "count public only" do
      assert_equal(
        @org.repositories.where(public: true).count,
        count_by_owner(@org, visibility: Repositories::RepositoryVisibility::Public)
      )
    end

    test "count private only" do
      assert_equal(
        @org.repositories.where(public: false).count,
        count_by_owner(@org, visibility: Repositories::RepositoryVisibility::Private)
      )
    end

    test "count internal only" do
      assert_equal(
        @org.internal_repositories.count,
        count_by_owner(@org, visibility: Repositories::RepositoryVisibility::Internal)
      )
    end

    test "count locked" do
      assert_equal(
        @org.repositories.where(locked: true).count,
        count_by_owner(@org, locked: true)
      )
    end

    test "count unlocked" do
      assert_equal(
        @org.repositories.where(locked: false).count,
        count_by_owner(@org, locked: false)
      )
    end

    test "only network roots" do
      assert_equal(
        @org.repositories.network_roots.count,
        count_by_owner(@org, network_roots: true)
      )
    end
  end

  def count_by_owner(owner, visibility: nil, locked: nil, network_roots: false, limit: nil)
    domain.total_active_count_by_owner(
      owner_id: owner.id,
      visibility:,
      locked:,
      network_roots:,
      limit:
    )
  end
end
