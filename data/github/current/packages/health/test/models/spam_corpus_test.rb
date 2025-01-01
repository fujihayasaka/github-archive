# typed: true
# frozen_string_literal: true

require "test_helper"

module SpamCorpusTestHelper
  def gist_test_content_array
    [
      { name: "1", value: "random content" },
    ]
  end
end

class SpamCorpusTest < GitHub::TestCase
  include SpamCorpusTestHelper

  fixtures do
    @owner          = create(:user)
    @commit_comment = create :commit_comment, user: @owner, body: "Yo"
    @issue_comment  = create :issue_comment,  user: @owner, body: "Yo"
    @public_repo    = create(:public_repository, owner: @owner)
    @issue          = create :issue,         user: @owner, body: "Yo",
                                         title: "Bubbles",
                                         repository: @public_repo

    @gist = GistHelpers.generate(contents: gist_test_content_array,
                           user: @owner,
                           created_at: 5.minutes.ago,
                           updated_at: 5.minutes.ago,
                         )
    @gist_comment   = @gist.comments.create(body: "Lorem to the ipsum", user: @owner)
  end

  context "creating a SpamCorpus instance" do
    test "is invalid without data" do
      sc = SpamCorpus.new(spam: false)
      refute sc.valid?
      assert sc.errors.full_messages.include? "Data can't be blank"
    end

    test "is invalid without spam flag specified" do
      sc = SpamCorpus.new(data: "foo")
      refute sc.valid?
      assert sc.errors.full_messages.include? "Spam is not included in the list"
    end

    test "is valid when data is present and spam is true" do
      sc = SpamCorpus.new(data: "foo", spam: true)
      assert sc.valid?
    end

    test "is valid when data is present and spam is false" do
      sc = SpamCorpus.new(data: "foo", spam: false)
      assert sc.valid?
    end
  end

  context "creating from a Gist" do
    test "captures body text" do
      sc = SpamCorpus.from_gist(@gist, false)
      assert_equal sc.data, gist_test_content_array[0][:value]
    end

    test "sets source_class correctly" do
      sc = SpamCorpus.from_gist(@gist, false)
      assert_equal sc.source_type, @gist.class.to_s
    end
  end

  context "creating from a CommitComment" do
    test "captures body text" do
      sc = SpamCorpus.from_comment(@commit_comment, false)
      assert_equal sc.data, @commit_comment.body
    end

    test "sets source_class correctly" do
      sc = SpamCorpus.from_comment(@commit_comment, false)
      assert_equal sc.source_type, @commit_comment.class.to_s
    end
  end

  context "creating from a GistComment" do
    test "captures body text" do
      sc = SpamCorpus.from_comment(@gist_comment, false)
      assert_equal sc.data, @gist_comment.body
    end

    test "sets source_class correctly" do
      sc = SpamCorpus.from_comment(@gist_comment, false)
      assert_equal sc.source_type, @gist_comment.class.to_s
    end
  end

  context "creating from an Issue" do
    test "captures title and body text" do
      sc = SpamCorpus.from_issue(@issue, false)
      assert_match /#{@issue.title}/, sc.data
      assert_match /#{@issue.body}/,  sc.data
    end

    test "sets source_class correctly" do
      sc = SpamCorpus.from_issue(@issue, false)
      assert_equal sc.source_type, @issue.class.to_s
    end
  end

  context "creating from an IssueComment" do
    test "captures body text" do
      sc = SpamCorpus.from_comment(@issue_comment, false)
      assert_equal sc.data, @issue_comment.body
    end

    test "sets source_class correctly" do
      sc = SpamCorpus.from_comment(@issue_comment, false)
      assert_equal sc.source_type, @issue_comment.class.to_s
    end
  end
end
