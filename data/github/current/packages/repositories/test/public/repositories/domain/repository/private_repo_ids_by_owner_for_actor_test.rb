# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../domain_test"

class Repositories::Domain::PrivateRepoIdsByOwnerForActorTest < Repositories::DomainTest

  fixtures do
    @org = create :organization
    @private_repos = create_list :private_repository, 3, owner: @org
    @user = create :user
    @org.add_member @user
  end

  context "#private_repo_ids_by_owner_for_actor" do
    test "finds private repo ids accessible for the user and org" do
      assert_query_count_per_table({ repositories: 2 }) do
        assert_same_elements(
          @private_repos.pluck(:id),
          domain.private_repo_ids_by_owner_for_actor(owner_id: @org.id, resource: "metadata")
        )
      end
    end

    test "returns nothing if the user has no access to the org" do
      another_org = create :organization
      create :private_repository, owner: another_org
      assert_equal [], domain.private_repo_ids_by_owner_for_actor(owner_id: another_org.id, resource: "metadata")
    end

    test "returns nothing if no user" do
      another_org = create :organization
      create :private_repository, owner: another_org
      assert_equal [], Repositories::Domain.new(:test, actor: nil).private_repo_ids_by_owner_for_actor(owner_id: another_org.id, resource: "metadata")
    end

    test "excludes private repo that's not accessible until it's granted individual access" do
      @org.update_default_repository_permission(:none, actor: @user)
      @hidden_repo = create :private_repository, owner: @org

      assert_same_elements(
        @private_repos.pluck(:id),
        domain.private_repo_ids_by_owner_for_actor(owner_id: @org.id, resource: "metadata")
      )

      @hidden_repo.add_member @user

      assert_same_elements(
        @private_repos.pluck(:id) + [@hidden_repo.id],
        domain.private_repo_ids_by_owner_for_actor(owner_id: @org.id, resource: "metadata")
      )
    end
  end
end
