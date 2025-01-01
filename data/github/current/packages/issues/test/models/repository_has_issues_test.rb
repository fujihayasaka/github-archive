# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryHasIssuesTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  test "disabling issues removes them from the search index" do
    assert @repo.has_issues

    assert_enqueued_with(job: RemoveFromSearchIndexJob, args: ["bulk_issues", @repo.id], queue: "index_high") do
      @repo.update! has_issues: false
    end
  end

  test "enabling issues adds them to the search index" do
    @repo.update! has_issues: false
    refute @repo.has_issues

    now = Time.now
    timestamp = Timestamp.from_time(now)
    guid = AddToSearchIndexJob.guid("bulk_issues", @repo.id)

    Timecop.freeze(now) do
      assert_enqueued_with(job: AddToSearchIndexJob, args: ["bulk_issues", @repo.id, { "submitted_at" => timestamp, "guid" => guid }], queue: "index_low") do
        @repo.update! has_issues: true
      end
    end
  end
end
