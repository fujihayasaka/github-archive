# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../domain_test"

class Repositories::Domain::ByOwnerAndTypeForActorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @another_user = create(:user)

    @repo_ids = (0..2).map do |_|
      create(:repository, owner: @user).id
    end
    @private_repo = create(:private_repository, owner: @user)
  end

  context "#by_owner_and_type_for_actor" do
    test "finds repos, owner is viewer" do
      domain = Repositories::Domain.new
      repos = domain.by_owner_and_type_for_actor(
        owner: @user,
        type: nil,
        pagination: GH::Pagination::Offset.new(page: 1, per_page: 4),
        sort: Repositories::SortBy::Id,
        direction: GH::Pagination::Sort::Direction::ASC,
        public_only: true
      )

      assert_equal @repo_ids.sort, repos.map(&:id)
      refute_includes repos.map(&:id), @private_repo.id
    end

    test "finds repos, owner is viewer, includes private" do
      GH.context.act_as(@user)
      domain = Repositories::Domain.new
      repos = domain.by_owner_and_type_for_actor(
        owner: @user,
        type: nil,
        pagination: GH::Pagination::Offset.new(page: 1, per_page: 4),
        sort: Repositories::SortBy::Id,
        direction: GH::Pagination::Sort::Direction::ASC,
        public_only: false
      )

      assert_equal (@repo_ids + [@private_repo.id]).sort, repos.map(&:id)
    end

    test "finds repos, owner is not viewer and viewer does not have access to private repo" do
      domain = Repositories::Domain.new
      repos = domain.by_owner_and_type_for_actor(
        owner: @user,
        type: nil,
        pagination: GH::Pagination::Offset.new(page: 1, per_page: 4),
        sort: Repositories::SortBy::Id,
        direction: GH::Pagination::Sort::Direction::ASC,
        public_only: false
      )

      assert_equal @repo_ids.sort, repos.map(&:id)
      refute_includes repos.map(&:id), @private_repo.id
    end
  end
end
