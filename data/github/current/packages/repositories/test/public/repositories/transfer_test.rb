# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::TransferTest < GitHub::TestCase
  fixtures do
    @new_owner = create(:user)

    @repo_a = create(:repository)
    @repo_b = create(:repository)
  end

  context ".any_in_progress?" do
    test "returns true if all of the repos are marked as 'transfer in progress'" do
      RepositoryOrchestration.transfer_type.create(repository: @repo_a).update(state: :running)
      RepositoryOrchestration.transfer_type.create(repository: @repo_b).update(state: :running)

      assert @repo_a.transfer_in_progress?
      assert @repo_b.transfer_in_progress?

      assert Repositories::Transfer.any_in_progress?([@repo_a, @repo_b])
    end

    test "returns true any of the repos are marked as 'transfer in progress'" do
      RepositoryOrchestration.transfer_type.create(repository: @repo_a).update(state: :running)

      assert @repo_a.transfer_in_progress?
      refute @repo_b.transfer_in_progress?

      assert Repositories::Transfer.any_in_progress?([@repo_a, @repo_b])
    end

    test "returns false if none of the repos are marked as 'transfer in progress'" do
      refute_predicate @repo_a, :transfer_in_progress?
      refute_predicate @repo_b, :transfer_in_progress?

      refute Repositories::Transfer.any_in_progress?([@repo_a, @repo_b])
    end
  end
end
