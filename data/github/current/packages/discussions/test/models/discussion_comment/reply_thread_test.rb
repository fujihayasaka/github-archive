# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionCommentReplyThreadTest < GitHub::TestCase
  # Use an arbitrary fixed timestamp to anchor test fixture timestamps to avoid unpleasant surprises from time in the
  # Real World :tm:. Using Jan 1 has the side benefit that it's immediately obvious if a particular timestamp is before
  # or after LAST_READ_AT because the times before are in 2020.
  LAST_READ_AT = Time.new(2021, 1, 1).utc.in_time_zone

  # So we don't have to type out this whole thing every time
  N = DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT

  fixtures do
    @user = create(:user)
    @discussion = create(:discussion)
    @parent = create(:discussion_comment, discussion: @discussion, repository: @discussion.repository)
  end

  def create_replies(n, parent: @parent)
    build_list(
      :discussion_comment, n, parent_comment: parent, discussion: @discussion, repository: @discussion.repository
    ) { |reply, i| yield(reply, i) }
  end

  def create_older_replies(n, parent: @parent)
    create_replies(n, parent: parent) do |reply, i|
      reply.created_at = LAST_READ_AT - (n - i + 1).days
      reply.save!
    end
  end

  def create_newer_replies(n, parent: @parent)
    create_replies(n, parent: parent) do |reply, i|
      reply.created_at = LAST_READ_AT + (i + 1).days
      reply.save!
    end
  end

  test "no replies" do
    threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
    assert_equal 1, threads.size
    thread = threads.values.first

    refute_predicate thread, :has_older_replies?
    refute_predicate thread, :has_newer_replies?
    assert_equal @parent, thread.parent
    assert_predicate thread.replies, :empty?
  end

  test "fewer than N replies" do
    replies = create_newer_replies(N - 1)

    threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
    assert_equal 1, threads.size
    thread = threads.values.first

    refute_predicate thread, :has_older_replies?
    refute_predicate thread, :has_newer_replies?
    assert_equal @parent, thread.parent
    assert_equal replies, thread.replies
  end

  test "fewer than N replies newer than LAST_READ_AT" do
    older_replies = create_older_replies(5)
    newer_replies = create_newer_replies(N - 1)

    threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
    assert_equal 1, threads.size
    thread = threads.values.first

    assert_equal @parent, thread.parent
    expected_replies = [older_replies.last] + newer_replies
    assert_equal expected_replies, thread.replies

    assert_predicate thread, :has_older_replies?
    assert_equal 4, thread.older_count
    refute_predicate thread, :has_newer_replies?
  end

  test "more than N replies newer than LAST_READ_AT" do
    older_replies = create_older_replies(5)
    newer_replies = create_newer_replies(N + 2)

    threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
    assert_equal 1, threads.size
    thread = threads.values.first

    assert_equal @parent, thread.parent
    assert_equal newer_replies.first(N), thread.replies

    assert_predicate thread, :has_older_replies?
    assert_equal 5, thread.older_count
    assert_predicate thread, :has_newer_replies?
    assert_equal 2, thread.newer_count
  end

  context "without LAST_READ_AT" do
    test "fewer than N replies" do
      replies = create_replies(N - 1) do |reply, i|
        reply.created_at = i.days.from_now
        reply.save!
      end

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: nil)
      assert_equal 1, threads.size
      thread = threads.values.first

      refute_predicate thread, :has_older_replies?
      refute_predicate thread, :has_newer_replies?
      assert_equal @parent, thread.parent
      assert_equal replies, thread.replies
    end

    test "N replies" do
      replies = create_replies(N) do |reply, i|
        reply.created_at = i.days.from_now
        reply.save!
      end

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: nil)
      assert_equal 1, threads.size
      thread = threads.values.first

      refute_predicate thread, :has_older_replies?
      refute_predicate thread, :has_newer_replies?
      assert_equal @parent, thread.parent
      assert_equal replies, thread.replies
    end

    test "more than N replies" do
      replies = create_replies(N + 3) do |reply, i|
        reply.created_at = i.days.from_now
        reply.save!
      end

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: nil)
      assert_equal 1, threads.size
      thread = threads.values.first

      assert_predicate thread, :has_older_replies?
      assert_equal 3, thread.older_count
      refute_predicate thread, :has_newer_replies?
      assert_equal @parent, thread.parent
      assert_equal replies.last(N), thread.replies
    end
  end

  context "multiple threads" do
    test "ordered by creation time" do
      parent1 = create(:discussion_comment, discussion: @discussion, created_at: @parent.created_at + 1.day)
      replies1 = create_newer_replies(N + 1, parent: parent1)

      parent2 = create(:discussion_comment, discussion: @discussion, created_at: @parent.created_at + 2.days)
      replies2 = create_older_replies(N - 1, parent: parent2)

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
      assert_equal 3, threads.size

      thread0 = threads[@parent.id]
      assert_predicate thread0.replies, :empty?

      thread1 = threads[parent1.id]
      assert_equal replies1.first(N), thread1.replies

      thread2 = threads[parent2.id]
      assert_equal replies2, thread2.replies
    end
  end

  if GitHub.spamminess_check_enabled?
    context "spam" do
      test "excludes spammy comments for non-authors" do
        normal_reply = create(:discussion_comment, parent_comment: @parent, discussion: @discussion)
        spammy_reply = create(:spammy_discussion_comment, parent_comment: @parent, discussion: @discussion)

        spammy_parent = create(:spammy_discussion_comment, discussion: @discussion)

        threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
        assert_equal 1, threads.size
        thread = threads.values.first

        assert_equal @parent, thread.parent
        assert_equal [normal_reply], thread.replies

        anon_threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: nil, last_read_at: LAST_READ_AT)
        assert_equal 1, anon_threads.size
        anon_thread = anon_threads.values.first

        assert_equal @parent, anon_thread.parent
        assert_equal [normal_reply], anon_thread.replies

        spammer_threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion,
          viewer: spammy_reply.user, last_read_at: LAST_READ_AT)
        assert_equal 1, spammer_threads.size
        spammer_thread = spammer_threads.values.first

        assert_equal @parent, spammer_thread.parent
        assert_equal [normal_reply, spammy_reply], spammer_thread.replies
      end
    end
  end

  context ".for_parent_comment" do
    test "without an anchor_id" do
      create_newer_replies(2)

      thread = DiscussionComment::ReplyThread.for_parent_comment(@parent, viewer: @user)
      assert_equal @parent, thread.parent
      assert_empty thread.replies
      assert_equal 0, thread.older_count
      assert_equal 0, thread.newer_count
    end

    test "returns an empty thread with no replies" do
      thread = DiscussionComment::ReplyThread.for_parent_comment(@parent, viewer: @user, anchor_id: 0)
      assert_empty thread.replies
      assert_equal 0, thread.older_count
      assert_equal 0, thread.newer_count
    end

    test "with fewer than N replies" do
      older_replies = create_older_replies(1)
      newer_replies = create_newer_replies(N - 2)
      anchor_id = newer_replies.first.id

      thread = DiscussionComment::ReplyThread.for_parent_comment(@parent, viewer: @user, anchor_id: anchor_id)

      assert_equal newer_replies, thread.replies
      assert_equal 1, thread.older_count
      assert_equal 0, thread.newer_count
    end

    test "with no replies after anchor_id" do
      older_replies = create_older_replies(5)
      anchor_id = older_replies.last.id

      zero_thread = DiscussionComment::ReplyThread.for_parent_comment(@parent, viewer: @user, anchor_id: anchor_id)
      assert_equal older_replies.last(1), zero_thread.replies
      assert_equal 4, zero_thread.older_count
      assert_equal 0, zero_thread.newer_count

      older_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, older: 3)
      assert_equal older_replies.last(4), older_thread.replies
      assert_equal 1, older_thread.older_count
      assert_equal 0, older_thread.newer_count

      newer_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, newer: 30)
      assert_equal older_replies.last(1), newer_thread.replies
      assert_equal 4, newer_thread.older_count
      assert_equal 0, newer_thread.newer_count

      both_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, older: 2, newer: 5)
      assert_equal older_replies.last(3), both_thread.replies
      assert_equal 2, both_thread.older_count
      assert_equal 0, both_thread.newer_count
    end

    test "with fewer than N replies after anchor_id" do
      older_replies = create_older_replies(5)
      newer_replies = create_newer_replies(N - 1)
      anchor_id = newer_replies.first.id

      zero_thread = DiscussionComment::ReplyThread.for_parent_comment(@parent, viewer: @user, anchor_id: anchor_id)
      assert_equal newer_replies, zero_thread.replies
      assert_equal 5, zero_thread.older_count
      assert_equal 0, zero_thread.newer_count

      older_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, older: 3)
      assert_equal older_replies.last(3) + newer_replies, older_thread.replies
      assert_equal 2, older_thread.older_count
      assert_equal 0, older_thread.newer_count

      newer_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, newer: 7)
      assert_equal newer_replies, newer_thread.replies
      assert_equal 5, newer_thread.older_count
      assert_equal 0, newer_thread.newer_count

      both_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, older: 2, newer: 5)
      assert_equal older_replies.last(2) + newer_replies, both_thread.replies
      assert_equal 3, both_thread.older_count
      assert_equal 0, both_thread.newer_count
    end

    test "with N replies after anchor_id" do
      older_replies = create_older_replies(4)
      newer_replies = create_newer_replies(N)
      anchor_id = newer_replies.first.id

      zero_thread = DiscussionComment::ReplyThread.for_parent_comment(@parent, viewer: @user, anchor_id: anchor_id)
      assert_equal newer_replies, zero_thread.replies
      assert_equal 4, zero_thread.older_count
      assert_equal 0, zero_thread.newer_count

      older_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, older: 2)
      assert_equal older_replies.last(2) + newer_replies, older_thread.replies
      assert_equal 2, older_thread.older_count
      assert_equal 0, older_thread.newer_count

      newer_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, newer: 1)
      assert_equal newer_replies, newer_thread.replies
      assert_equal 4, newer_thread.older_count
      assert_equal 0, newer_thread.newer_count

      both_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, older: 3, newer: 2)
      assert_equal older_replies.last(3) + newer_replies, both_thread.replies
      assert_equal 1, both_thread.older_count
      assert_equal 0, both_thread.newer_count
    end

    test "with more than N replies after anchor_id" do
      older_replies = create_older_replies(6)
      newer_replies = create_newer_replies(N + 2)
      anchor_id = newer_replies.first.id

      zero_thread = DiscussionComment::ReplyThread.for_parent_comment(@parent, viewer: @user, anchor_id: anchor_id)
      assert_equal newer_replies.first(N), zero_thread.replies
      assert_equal 6, zero_thread.older_count
      assert_equal 2, zero_thread.newer_count

      older_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, older: 4)
      assert_equal older_replies.last(4) + newer_replies.first(N), older_thread.replies
      assert_equal 2, older_thread.older_count
      assert_equal 2, older_thread.newer_count

      newer_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, newer: 1)
      assert_equal newer_replies.first(N + 1), newer_thread.replies
      assert_equal 6, newer_thread.older_count
      assert_equal 1, newer_thread.newer_count

      both_thread = DiscussionComment::ReplyThread.for_parent_comment(
        @parent, viewer: @user, anchor_id: anchor_id, older: 3, newer: 1)
      assert_equal older_replies.last(3) + newer_replies.first(N + 1), both_thread.replies
      assert_equal 3, both_thread.older_count
      assert_equal 1, both_thread.newer_count
    end
  end

  context "count_newer_than" do
    test "returns 0 with no last_read_at timestamp" do
      create_older_replies(2)
      create_newer_replies(2)

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
      assert_equal 1, threads.size
      thread = threads.values.first

      assert_equal 0, thread.count_newer_than(nil)
    end

    test "when there were more than N new replies" do
      create_older_replies(5)
      create_newer_replies(N + 3)

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
      assert_equal 1, threads.size
      thread = threads.values.first

      assert_equal N + 3, thread.count_newer_than(LAST_READ_AT)
    end

    test "when there were fewer than N new replies" do
      create_older_replies(5)
      create_newer_replies(N - 1)

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
      assert_equal 1, threads.size
      thread = threads.values.first

      assert_equal N - 1, thread.count_newer_than(LAST_READ_AT)
    end
  end

  context "total_reply_count" do
    test "with fewer than N replies" do
      create_newer_replies(N - 2)

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
      assert_equal 1, threads.size
      thread = threads.values.first

      assert_equal N - 2, thread.total_reply_count
    end

    test "with N replies" do
      create_older_replies(1)
      create_newer_replies(N - 1)

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
      assert_equal 1, threads.size
      thread = threads.values.first

      assert_equal N, thread.total_reply_count
    end

    test "with more than N replies" do
      create_older_replies(2)
      create_newer_replies(N + 2)

      threads = DiscussionComment::ReplyThread.all_from_discussion(@discussion, viewer: @user, last_read_at: LAST_READ_AT)
      assert_equal 1, threads.size
      thread = threads.values.first

      assert_equal N + 4, thread.total_reply_count
    end

    test "with initial count of replies" do
      initial_count = 3
      create_older_replies(1)
      create_newer_replies(initial_count - 1)

      threads = DiscussionComment::ReplyThread.all_from_discussion(
        @discussion,
        viewer: @user,
        last_read_at: LAST_READ_AT,
        initial_count: initial_count
      )
      assert_equal 1, threads.size
      thread = threads.values.first

      assert_equal initial_count, thread.total_reply_count
    end

    test "loads hidden comments" do
      initial_count = 3
      create_older_replies(1)
      create_newer_replies(initial_count - 1)
      parent_1 = create(:discussion_comment, discussion: @discussion, repository: @discussion.repository)
      parent_2 = create(:discussion_comment, discussion: @discussion, repository: @discussion.repository)
      create_newer_replies(initial_count + 5, parent: parent_1)
      create_newer_replies(initial_count + 5, parent: parent_2)

      threads = DiscussionComment::ReplyThread.all_from_discussion(
        @discussion,
        viewer: @user,
        items_per_page: 2,
        last_read_at: LAST_READ_AT,
        initial_count: initial_count,
      )
      assert_equal 3, threads.size
      first_thread = threads.values[0]
      hidden_thread = threads.values[1]
      last_thread = threads.values[2]

      assert_equal initial_count, first_thread.replies.size
      assert_equal initial_count, hidden_thread.replies.size
      assert_equal initial_count, last_thread.replies.size
    end

    test "loads all comments + threads when items per page isn't set" do
      initial_count = 3
      create_older_replies(1)
      create_newer_replies(initial_count - 1)
      parent_1 = create(:discussion_comment, discussion: @discussion, repository: @discussion.repository)
      parent_2 = create(:discussion_comment, discussion: @discussion, repository: @discussion.repository)
      create_newer_replies(initial_count + 5, parent: parent_1)
      create_newer_replies(initial_count + 5, parent: parent_2)

      threads = DiscussionComment::ReplyThread.all_from_discussion(
        @discussion,
        viewer: @user,
        last_read_at: LAST_READ_AT,
        initial_count: initial_count
      )
      assert_equal 3, threads.size
      first_thread = threads.values[0]
      hidden_thread = threads.values[1]
      last_thread = threads.values[2]

      assert_equal initial_count, first_thread.replies.size
      assert_equal initial_count, hidden_thread.replies.size
      assert_equal initial_count, last_thread.replies.size
    end
  end
end
