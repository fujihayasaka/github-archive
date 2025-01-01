# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncSponsorsSearchIndicesJobTest < GitHub::TestCase
  include JobTestHelper

  if GitHub.sponsors_enabled?
    fixtures do
      @sponsorable = create(:user, :sponsorable)
      @sponsorable_guid = AddToSearchIndexJob.guid("user", @sponsorable.id)
      @repo1 = create(:repository, owner: @sponsorable)
      @repo2 = create(:private_repository, owner: @sponsorable)
      @repo_guid1 = AddToSearchIndexJob.guid("repository", @repo1.id)
      @repo_guid2 = AddToSearchIndexJob.guid("repository", @repo2.id)
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: SyncSponsorsSearchIndicesJob, args: [sponsorable: @sponsorable]
    end

    context "#perform" do
      test "kicks off a AddToSearchIndexJob for each of the sponsorable's repos" do
        freeze_time do
          timestamp = Timestamp.from_time(Time.now)
          assert_enqueued_with(
            job: AddToSearchIndexJob,
            args: ["repository", @repo1.id, { "submitted_at" => timestamp, "guid" => @repo_guid1 }]
          ) do
            assert_enqueued_with(
              job: AddToSearchIndexJob,
              args: ["repository", @repo2.id, { "submitted_at" => timestamp, "guid" => @repo_guid2 }]
            ) do
              assert_enqueued_with(
                job: AddToSearchIndexJob,
                args: ["user", @sponsorable.id, { "submitted_at" => timestamp, "guid" => @sponsorable_guid }]
              ) do
                SyncSponsorsSearchIndicesJob.perform_now(sponsorable: @sponsorable)
              end
            end
          end
        end
      end
    end
  end
end
