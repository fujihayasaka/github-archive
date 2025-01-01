# typed: true
# frozen_string_literal: true

require "test_helper"

class ReleaseMentionsTest < Api::TestCase
  include UploadableTestHelpers

  fixtures do
    @user = create(:user)
    @user2 = create :user, name: "Contributor-2"
    @user3 = create :user, name: "cOnTrIbUtOr-3-5678901234567890123456789"
    @user4 = create :user, name: "co4"

    @repo = create :repository, owner: @user, from_example: :repository_test_simple
  end

  test "no mentions" do
    rel = create :release, repository: @repo, author: @user, body: "this body has no mentions"
    assert_equal 0, rel.mentions.count
  end

  test "ignore mentions with ending punctuation" do
    rel = create :release, repository: @repo, author: @user, body: "hey @#{@user}- @#{@user2}.com hello"
    assert_equal 0, rel.mentions.count
  end

  test "ignore mentions in code blocks" do
    rel = create :release, repository: @repo, author: @user, body: "`foo = @#{@user} - @#{@user2}`"
    assert_equal 0, rel.mentions.count
  end

  test "update mentions" do
    rel = create :release, repository: @repo, author: @user, body: "hey @#{@user} - hello"
    assert_equal 1, rel.mentions.count
    assert_equal @user, rel.mentions[0]

    # trailing exclamation point appears to be allowed
    rel = Release.update(rel.id, body: "updated @#{@user2} and @#{@user3}!")
    assert_equal 2, rel.mentions.count
    assert_same_elements [@user2, @user3], rel.mentions
  end

  test "duplicate mentions are pruned" do
    body = <<~EOS.chomp
    First @fakeuser77 did something, @#{@user} @#{@user} are duplicates
    So are @#{@user4} @#{@user2}
    So are @#{@user4} @#{@user2}
    EOS
    rel = create :release, repository: @repo, author: @user, body: body
    assert_equal 3, rel.mentions.count
    assert_same_elements [@user, @user4, @user2], rel.mentions
  end

  test "more complicated example" do
    body = <<~EOS.chomp
    ## What Changed
    @#{@user} did something
    (@#{@user4}) says hi
    [@#{@user2}] made a change
    What about @#{@user3}? let's mention them.
    Shout out to @typoUser and @nonexistentBob
    Also duplicate mention for @#{@user4} and @#{@user2}
    Nothing goes here.
    EOS

    rel = create :release, repository: @repo, author: @user, body: body
    assert_equal 4, rel.mentions.count
    assert_same_elements [@user, @user4, @user2, @user3], rel.mentions
  end

  test "destroying a release destroys the mentions" do
    rel = create :release, repository: @repo, author: @user, body: "hey @#{@user2} and @#{@user3}!"
    assert_equal 2, rel.mentions.count
    assert_equal @user2, rel.mentions[0]
    assert_equal @user3, rel.mentions[1]
    assert_equal 1, @user2.release_mentions.count

    assert_difference("@user2.release_mentions.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { rel.destroy }
    end

    refute Release.exists?(rel.id)
  end

  test "destroying a user destroys their mentions" do
    ex_user = create :user, name: "destroy-me"

    rel = create :release, repository: @repo, author: @user, body: "hey @#{ex_user} and @#{@user3}!"
    assert_equal 2, rel.mentions.count
    assert_equal ex_user, rel.mentions[0]
    assert_equal @user3, rel.mentions[1]

    repo2 = create :repository, owner: @user, from_example: :repository_test_simple
    rel2 = create :release, repository: repo2, author: @user, body: "hey @#{ex_user} and @#{@user3}!"
    assert_equal 2, rel2.mentions.count
    assert_equal ex_user, rel2.mentions[0]
    assert_equal @user3, rel2.mentions[1]

    assert_difference("rel.mentions.count", -1) do
      assert_difference("rel2.mentions.count", -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { ex_user.destroy }
      end
    end

    refute User.exists?(ex_user.id)
  end

  test "number of mentions are limited", skip_unless: :prevent_mention_spam? do
    body = "@#{@user} @#{@user2} @#{@user4}"
    Release.stub_const(:MENTION_LIMIT, 1) do
      rel = create :release, repository: @repo, author: @user, body: body
      assert_equal 1, rel.mentions.count
      assert_same_elements [@user], rel.mentions
    end
  end

  test "serialization" do
    user = create(:verified_user)
    repo = create(:repository, from_example: :tags_galore)
    release = create(:release,
      name: "v1.0",
      tag_name: "v1.0",
      author: repo.owner,
      repository: repo,
      target_commitish: "master",
      body: "thanks @#{repo.owner} and @#{user}",
    )

    expected_user_fields = [
      :avatar_url,
      :login,
      :profile_name,
      :profile_url,
      :avatar_user_actor
    ]

    # serialize the users directly
    hashes = Api::Serializer.serialize(:user_avatar_hash, [repo.owner, user])

    # mentions are included for the Stratocaster event
    event = Stratocaster::Event.new(
      event_type: "ReleaseEvent",
      payload: {
        release: Api::Serializer.serialize(:release_hash, release, { include_mentions: true }),
      },
    )

    assert_equal 2, event.payload[:release][:mentions].count
    assert_same_elements hashes, event.payload[:release][:mentions]
    assert_same_elements expected_user_fields, hashes.first.keys
  end
end
