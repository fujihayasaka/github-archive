# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositorySearchDependencyTest < GitHub::TestCase
  fixtures do
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")

    @grit     = create(:repository, name: "grit",     owner: @mojombo)
  end

  test "#synchronize_search_index does not update the search index for locked repositories" do
    @grit.lock_for_billing
    assert_enqueued_jobs 0 do
      @grit.synchronize_search_index
    end
  end

  test "#synchronize_search_index removes deleted repositories which are also locked from the search index" do
    @grit.lock_for_billing
    @grit.update active: nil

    reset_job_hash_locks

    assert_enqueued_with job: RemoveFromSearchIndexJob do
      @grit.reload.synchronize_search_index
    end
  end
end
