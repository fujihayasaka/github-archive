# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../domain_test"

class Repositories::Domain::RecentByOwnerIdsTest < Repositories::DomainTest

  fixtures do
    @organizations = create_list(:organization, 15)
    @users = create_list(:user, 15)
    @repositories = @organizations.map { |org| create_list(:repository, 5, owner: org) }.flatten
    @repositories += @users.map { |user| create_list(:repository, 5, owner: user) }.flatten
    range = (0..@repositories.size - 1).to_a
    @repositories = @repositories.shuffle.map do |repo|
      days_ago = range.pop.days.ago
      repo.update!(pushed_at: days_ago)
      repo
    end.sort_by(&:pushed_at).reverse
  end

  context "#recent_by_owner_ids" do
    test "returns the most recently pushed repositories for the given owner ids" do
      limit = 100
      expected_repo_ids = @repositories.map(&:id).first(limit)
      assert_same_elements(
        expected_repo_ids,
        domain.recent_by_owner_ids(owner_ids: @organizations.map(&:id) + @users.map(&:id), limit: limit)
      )
    end

    test "returns the most recently pushed repositories for the given owner ids, excluding some" do
      owner_ids = (@organizations.map(&:id) + @users.map(&:id)).sample(20)
      expected_repo_ids = @repositories.select { |repo| owner_ids.include?(repo.owner_id) }.map(&:id).first(100)
      assert_same_elements(
        expected_repo_ids,
        domain.recent_by_owner_ids(owner_ids: owner_ids, limit: 100)
      )
    end

    test "returns the most recently pushed repository for the given owner ids" do
      limit = 1
      expected_repo_ids = @repositories.map(&:id).first(limit)
      assert_same_elements(
        expected_repo_ids,
        domain.recent_by_owner_ids(owner_ids: @organizations.map(&:id) + @users.map(&:id), limit: limit)
      )
    end

    test "returns the most recently pushed repositories by one owner " do
      expected_repo_ids = @repositories.select { |repo| repo.owner_id == @organizations.first.id }.map(&:id).first(100)
      assert_same_elements(
        expected_repo_ids,
        domain.recent_by_owner_ids(owner_ids: [@organizations.first.id], limit: 100)
      )
    end

    test "raises an error if the limit is greater than 100" do
      assert_raises(Repositories::Domain::Error::UnprocessableError, "limit must be 100 or fewer") do
        domain.recent_by_owner_ids(owner_ids: @organizations.map(&:id) + @users.map(&:id), limit: 101)
      end
    end

    test "raises an error if the owner ids size is greater than 30" do
      owner_ids = @organizations.map(&:id) + @users.map(&:id) + [create(:user).id]
      assert_raises(Repositories::Domain::Error::UnprocessableError, "owner_ids must be 30 or fewer") do
        domain.recent_by_owner_ids(owner_ids: owner_ids, limit: 100)
      end
    end
  end
end
