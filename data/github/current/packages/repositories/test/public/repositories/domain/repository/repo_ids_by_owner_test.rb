# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../domain_test"

class Repositories::Domain::RepoIdsByOwnerTest < Repositories::DomainTest

  fixtures do
    @user = create(:user)
    @repo_ids = (0..2).map do |_|
      create(:repository, owner: @user).id
    end

    @another_user_repo = create(:repository, owner: create(:user))
    @repo_ids << @another_user_repo.id

    @private_repo = create(:private_repository, owner: @user)
    @repo_ids << @private_repo.id

    @inactive_repo = create(:repository, owner: @user, active: false)
    @repo_ids << @inactive_repo.id
  end

  context "#repo_ids_by_owner" do
    test "finds repo ids by owner with no filter" do
      expected_repo_ids = @repo_ids - [@another_user_repo.id]

      assert_sql_queries(["SELECT repositories.id FROM repositories WHERE repositories.owner_id = ?"]) do
        assert_same_elements(
          expected_repo_ids,
          domain.repo_ids_by_owner(
            owner_id: @user.id,
            repo_ids_in: nil,
            public_only: false,
            active_only: false
          )
        )
      end

      # drop the inactive repo
      @repo_ids.pop
      expected_repo_ids = @repo_ids - [@another_user_repo.id]
      assert_same_elements(
        expected_repo_ids,
        domain.repo_ids_by_owner(
          owner_id: @user.id,
          repo_ids_in: nil,
          public_only: false,
          active_only: true
        )
      )

      # drop the private repo
      @repo_ids.pop
      expected_repo_ids = @repo_ids - [@another_user_repo.id]
      assert_same_elements(
        expected_repo_ids,
        domain.repo_ids_by_owner(
          owner_id: @user.id,
          repo_ids_in: nil,
          public_only: true,
          active_only: true
        )
      )
    end

    test "finds repo ids by owner using SQL id IN clause" do
      # drop the first repo
      @repo_ids.delete_at(1)

      expected_repo_ids = @repo_ids - [@another_user_repo.id]
      assert_sql_queries(["SELECT repositories.id FROM repositories WHERE repositories.owner_id = ? AND repositories.id IN ?"]) do
        assert_same_elements(
          expected_repo_ids,
          domain.repo_ids_by_owner(
            owner_id: @user.id,
            repo_ids_in: @repo_ids,
            public_only: false,
            active_only: false
          )
        )
      end

      # drop the inactive repo
      @repo_ids.pop
      expected_repo_ids = @repo_ids - [@another_user_repo.id]
      assert_same_elements(
        expected_repo_ids,
        domain.repo_ids_by_owner(
          owner_id: @user.id,
          repo_ids_in: @repo_ids,
          public_only: false,
          active_only: true
        )
      )

      # drop the private repo
      @repo_ids.pop
      expected_repo_ids = @repo_ids - [@another_user_repo.id]
      assert_same_elements(
        expected_repo_ids,
        domain.repo_ids_by_owner(
          owner_id: @user.id,
          repo_ids_in: @repo_ids,
          public_only: true,
          active_only: true
        )
      )
    end

    test "finds repo ids by owner using batched scope + load_async" do
      domain.stubs(:use_sql_id_in_clause?).with(any_parameters).returns(false)
      Repositories::Domain.stub_const(:MAX_REPOSITORY_ID_IN_CLAUSE_SIZE, 2) do
        expected_repo_ids = @repo_ids - [@another_user_repo.id]
        queries = [
          "SELECT repositories.id FROM repositories WHERE repositories.owner_id = ? AND repositories.id IN ?",
          "SELECT repositories.id FROM repositories WHERE repositories.owner_id = ? AND repositories.id IN ?",
          "SELECT repositories.id FROM repositories WHERE repositories.owner_id = ? AND repositories.id IN ?",
        ]
        assert_sql_queries(queries) do
          assert_same_elements(
            expected_repo_ids,
            domain.repo_ids_by_owner(
              owner_id: @user.id,
              repo_ids_in: @repo_ids + @repo_ids, # duplicate the repo ids
              public_only: false,
              active_only: false
            )
          )
        end

        # drop the inactive repo
        @repo_ids.pop
        expected_repo_ids = @repo_ids - [@another_user_repo.id]
        assert_same_elements(
          expected_repo_ids,
          domain.repo_ids_by_owner(
            owner_id: @user.id,
            repo_ids_in: @repo_ids,
            public_only: false,
            active_only: true
          )
        )

        # drop the private repo
        @repo_ids.pop
        expected_repo_ids = @repo_ids - [@another_user_repo.id]
        assert_same_elements(
          expected_repo_ids,
          domain.repo_ids_by_owner(
            owner_id: @user.id,
            repo_ids_in: @repo_ids,
            public_only: true,
            active_only: true
          )
        )
      end

      domain.unstub(:use_sql_id_in_clause?)
    end

    test "find no repo ids by owner with filter is an empty array" do
      assert_no_queries do
        assert_empty(domain.repo_ids_by_owner(owner_id: @user.id, repo_ids_in: []))
      end
    end
  end
end
