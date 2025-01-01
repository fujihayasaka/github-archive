# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionSearchAdapterTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, has_discussions: true)
    @discussion = create(:discussion, repository: @repo)
  end

  context "#parent_repo_is_searchable?" do
    test "false when the repository is DMCA disabled" do
      staff = create(:staff_admin_user)
      @repo.access.disable("dmca", staff,
        dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")

      refute_predicate @discussion, :parent_repo_is_searchable?
    end unless GitHub.enterprise?

    test "false when the repository is not active" do
      Repository.any_instance.stubs(:active?).returns(false)

      refute_predicate @discussion, :parent_repo_is_searchable?
    end

    test "false when the repository is spammy" do
      Repository.any_instance.stubs(:spammy?).returns(true)

      refute_predicate @discussion, :parent_repo_is_searchable?
    end if GitHub.spamminess_check_enabled?

    test "false when the repository is disabled" do
      Repository.any_instance.stubs(:disabled?).returns(true)

      refute_predicate @discussion, :parent_repo_is_searchable?
    end

    test "true when repo is elgible and can have discussions" do
      assert_predicate @discussion, :parent_repo_is_searchable?
    end
  end

  context "#synchronize_search_index" do
    test "adds new discussion to search index" do
      Timecop.freeze do
        new_discussion = create(:discussion, repository: @repo)
        guid = AddToSearchIndexJob.guid("discussion", new_discussion.id)
        assert_enqueued_with job: AddToSearchIndexJob, args: ["discussion", new_discussion.id, {
          "submitted_at" => Timestamp.from_time(Time.now), "guid" => guid
        }]
      end
    end

    test "reindexes discussion on change" do
      @discussion.title = "Something borrowed, something blue"
      guid = AddToSearchIndexJob.guid("discussion", @discussion.id)

      Timecop.freeze do
        assert_enqueued_with(job: AddToSearchIndexJob, args: ["discussion", @discussion.id, {
          "submitted_at" => Timestamp.from_time(Time.now), "guid" => guid
        }]) do
          assert @discussion.save
        end
      end
    end

    test "reindexes discussion when a comment is added" do
      guid = AddToSearchIndexJob.guid("discussion", @discussion.id)

      Timecop.freeze do
        assert_enqueued_with(job: AddToSearchIndexJob, args: ["discussion", @discussion.id, {
          "submitted_at" => Timestamp.from_time(Time.now), "guid" => guid
        }]) do
          create(:discussion_comment, discussion: @discussion)
        end
      end
    end
  end
end
