# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateOwnerRepositorySponsorablesJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsorable = create(:user, :verified)
    @repo1, @repo2, @repo3 = create_list(:repository, 3, owner: @sponsorable)
    @sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @sponsorable)
    @repo_sponsorable1 = create(:repository_sponsorable, sponsorable: @sponsorable, repository: @repo1,
      source: :owner)

    # Make a repo-sponsorable that should be deleted because the owner will no longer be the sponsorable:
    @repo_sponsorable2 = create(:repository_sponsorable, sponsorable: @sponsorable, repository: @repo2,
      source: :owner)
    @repo2.owner = create(:user)
    @repo2.save!
  end

  if GitHub.sponsors_enabled?
    test "creates and deletes RepositorySponsorable records to match owned repos for the sponsorable" do
      UpdateOwnerRepositorySponsorablesJob.perform_now(sponsorable_id: @sponsorable.id)

      assert RepositorySponsorable.exists?(@repo_sponsorable1.id),
        "should have kept existing record for repo still owned by sponsorable"
      refute RepositorySponsorable.exists?(@repo_sponsorable2.id),
        "should have deleted record for repo no longer owned by sponsorable"
      new_repo_sponsorable = @sponsorable.repository_sponsorables.find_by(repository: @repo3)
      refute_nil new_repo_sponsorable, "should have created record for repo owned by sponsorable"
      assert_predicate new_repo_sponsorable, :owner?
    end

    test "deletes all RepositorySponsorable records when Sponsors listing is not approved" do
      @sponsors_listing.actor = @sponsorable
      @sponsors_listing.unpublish!

      assert_difference(-> { RepositorySponsorable.count }, -2) do
        UpdateOwnerRepositorySponsorablesJob.perform_now(sponsorable_id: @sponsorable.id)
      end

      refute RepositorySponsorable.exists?(@repo_sponsorable1.id)
      refute RepositorySponsorable.exists?(@repo_sponsorable2.id)
    end

    test "deletes all RepositorySponsorable records when no Sponsors listing exists for the sponsorable" do
      @sponsors_listing.delete

      assert_difference(-> { RepositorySponsorable.count }, -2) do
        UpdateOwnerRepositorySponsorablesJob.perform_now(sponsorable_id: @sponsorable.id)
      end

      refute RepositorySponsorable.exists?(@repo_sponsorable1.id)
      refute RepositorySponsorable.exists?(@repo_sponsorable2.id)
    end

    test "errors when creation fails for a RepositorySponsorable" do
      sponsorable = create(:user, :sponsorable)
      create(:repository, owner: sponsorable)
      RepositorySponsorable.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)

      assert_no_difference(-> { RepositorySponsorable.count }) do
        assert_raises(ActiveRecord::RecordInvalid) do
          UpdateOwnerRepositorySponsorablesJob.perform_now(sponsorable_id: sponsorable.id)
        end
      end
    end

    test "retries the job on dirty exit" do
      assert_retry_on_dirty_exit(job: UpdateOwnerRepositorySponsorablesJob, args: [{
        sponsorable_id: @sponsorable.id,
      }])
    end

    test "does not delete any RepositorySponsorable records where source is not 'owner'" do
      repo = create(:repository)
      create(:repository_preferred_file, :funding, repository: repo)
      repo_sponsorable = create(:repository_sponsorable, repository: repo, sponsorable: @sponsorable,
        source: :repo_funding_file)

      UpdateOwnerRepositorySponsorablesJob.perform_now(sponsorable_id: @sponsorable.id)

      assert RepositorySponsorable.exists?(repo_sponsorable.id)
    end
  else
    test "no-op when Sponsors is disabled" do
      assert_no_difference(-> { RepositorySponsorable.count }) do
        UpdateOwnerRepositorySponsorablesJob.perform_now(sponsorable_id: @sponsorable.id)
      end
      assert RepositorySponsorable.exists?(@repo_sponsorable1.id)
      assert RepositorySponsorable.exists?(@repo_sponsorable2.id)
    end
  end
end
