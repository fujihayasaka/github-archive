# typed: strict
# frozen_string_literal: true

require "test_helper"

class GitHubCommitMessageTest < GitHub::TestCase
  test "splitting subject and body in well formed messages" do
    text = "added stuff\n\nA lot more detail here\n"
    message = Commits::CommitMessage.new(text)
    assert_equal "added stuff", message.subject
    assert_equal "A lot more detail here", message.body
  end

  test "to_s and to_str" do
    text = "added stuff\n\nA lot more detail here\n"
    message = Commits::CommitMessage.new(text)
    assert_equal "added stuff\n\nA lot more detail here", message.to_s
    assert_equal "added stuff\n\nA lot more detail here", message.to_str
  end

  test "truncating long subjects" do
    text = "added stuff to the thing and did some other things that I'd " +
           "rather not talk about because it's crazy"
    message = Commits::CommitMessage.new(text)
    assert_equal "#{text[0, 69]}…", message.subject
    assert_equal "…#{text[69..-1]}", message.body
    assert message.body?
    assert_equal "#{text[0, 69]}…\n\n…#{text[69..-1]}", message.to_s
    assert_equal text, message.tooltip
  end

  test "adding truncated text to the body" do
    text = "added stuff to the thing and did some other things that I'd " +
           "rather not talk about because it's crazy\n\n" +
           "A lot more detail here"
    message = Commits::CommitMessage.new(text)
    assert_equal "#{text[0, 69]}…", message.subject
    assert_equal "…#{text[69..-1]}", message.body
    assert message.body?
  end

  test "truncating multi-byte characters" do
    text = "⇧⎋⌘ " * 16
    message = Commits::CommitMessage.new(text)
    assert_equal ("⇧⎋⌘ " * 13) + "⇧⎋⌘…", message.subject
    assert_equal "… ⇧⎋⌘ ⇧⎋⌘", message.body
  end

  test "truncating always produces a shorter subject" do
    1.upto(200) do |length|
      text = "a" * length
      message = Commits::CommitMessage.new(text)
      if message.subject == text
        # No truncation occurred.
        assert_nil message.body
      else
        assert message.subject.length < text.length, "Expected #{message.subject.inspect} (length=#{message.subject.length}) to be shorter than #{text.inspect} (length=#{text.length})"
        refute_nil message.body
      end
    end
  end

  test "truncating never generates a 1-, 2-, or 3-character body" do
    1.upto(200) do |length|
      text = "a" * length
      message = Commits::CommitMessage.new(text)
      if message.subject == text
        # No truncation occurred.
        assert_nil message.body
      else
        assert message.body.length >= 4, "Expected #{message.body.inspect} (length=#{message.body.length}) to be at least 4 characters long (generated from #{text.inspect} (length=#{text.length}))"
      end
    end
  end

  test "rstrips body" do
    text = " * abc \n * def\n * ghi "
    message = Commits::CommitMessage.new(text)
    assert_equal " * abc", message.subject
    assert_equal " * def\n * ghi", message.body
  end

  test "saving a commit message strips spammy unicode characters" do
    text = "added stuff " + "a" + ("\u034c" * 50) + " \nA lot more detail here " + "a" + ("\u034c" * 50) + " \n"
    message = Commits::CommitMessage.new(text)
    assert_equal "added stuff a", message.subject
    assert_equal "A lot more detail here a", message.body
  end

  test "saving a commit message maintains legitimate unicode characters" do
    text = "added stuff " + "a" + ("\u034c" * 3) + " \nA lot more detail here " + "a" + ("\u034c" * 3) + " \n"
    message = Commits::CommitMessage.new(text)
    assert_equal "added stuff a" + ("\u034c" * 3), message.subject
    assert_equal "A lot more detail here a" + ("\u034c" * 3), message.body
  end
end

class GitHubCommitMessageHtmlTest < GitHub::TestCase
  test "subject is html_safe" do
    text = "added stuff\n\nA lot more detail here\n"
    message = Commits::CommitMessageHTML.new(text)
    assert_predicate message.subject, :html_safe?
  end

  test "subjects that are URLs don't get wrapped in anchor tags" do
    text = "https://dangeroussite.com"
    message = Commits::CommitMessageHTML.new(text)
    assert_equal "https://dangeroussite.com", message.subject
  end

  test "subjects that are space-padded URLs don't get wrapped in anchor tags" do
    text = " https://dangeroussite.com"
    message = Commits::CommitMessageHTML.new(text)
    assert_equal " https://dangeroussite.com", message.subject
  end

  test "subjects that are PR URLs don't get modified or filtered" do
    owner = create(:user, login: "abc")
    repository = create(:repository, owner: owner, name: "commit-url-test", from_example: :pull_request_source)

    protected_branch = create(
      :protected_branch,
      repository: repository,
      name: "master",
    )

    pull_request = PullRequest.create_for!(repository,
      base: "master",
      head: "master-forward-2",
      user: owner,
      title: "Test PR",
    )

    text = pull_request.url
    message = Commits::CommitMessageHTML.new(text)
    assert_equal "https://github.com/abc/commit-url-test/pull/1", message.subject
  end

  test "splitting subject and body in well formed messages" do
    text = "added stuff\n\nA lot more detail here\n"
    message = Commits::CommitMessageHTML.new(text)
    assert_equal "added stuff", message.subject
    assert_equal "A lot more detail here", message.body
    assert_equal "added stuff\n\nA lot more detail here", message.to_s
  end

  test "truncating long subjects" do
    text = "added stuff to the thing and did some other things that I'd " +
           "rather not talk about because it's crazy"
    message = Commits::CommitMessageHTML.new(text)
    assert_equal_html "#{text[0, 69]}…", message.subject
    assert_equal_html "…#{text[69..-1]}", message.body
    assert message.body?
    assert_equal_html "#{text[0, 69]}…\n\n…#{text[69..-1]}", message.to_s
  end

  test "adding truncated text to the body" do
    text = "added stuff to the thing and did some other things that I'd " +
           "rather not talk about because it's crazy\n\n" +
           "A lot more detail here"
    message = Commits::CommitMessageHTML.new(text)
    assert_equal_html "#{text[0, 69]}…", message.subject
    assert_equal_html "…#{text[69..-1]}", message.body
    assert message.body?
  end

  test "adding truncated text to the longer body" do
    text = "added stuff to the thing and did some other things that I'd " +
           "rather not talk about because it's crazy and I am still typing" +
           "here with more information and I am really trying to make this a " +
           "longer commit message so here I am, still typing, still going" +
           "just will not quit making this a longer message becasue some people" +
           "have to do that and I am one of those people. So here we are, with a message" +
           "that is over 200 characters long. Yup. Doing the thing here. Just typing away."
    message = Commits::CommitMessageHTML.new(text)
    assert_equal_html "#{text[0, 197]}…", message.async_longer_subject.sync
    assert_equal_html "…#{text[197..-1]}", message.longer_body
    assert message.body?
  end

  test "truncating multi-byte characters" do
    text = "⇧⎋⌘ " * 16
    message = Commits::CommitMessageHTML.new(text)
    assert_equal ("⇧⎋⌘ " * 14).strip + "…", message.subject
    assert_equal "… ⇧⎋⌘ ⇧⎋⌘", message.body
  end

  test "truncating messages with invalid UTF-8 byte sequences" do
    text = "message\xE2\x89"
    message = Commits::CommitMessageHTML.new(text)
    assert_equal "message\uFFFD", message.subject
  end

  test "truncating autolinked URLs" do
    text = "yo this URL should be truncated " +
           "http://example.com/fuuuuuuuuuuuuuuuuuuuuuuu " +
           "and the overflow portion should be included in the body"
    message = Commits::CommitMessageHTML.new(text)
    assert_equal_html "yo this URL should be truncated " +
      "<a href=\"http://example.com/fuuuuuuuuuuuuuuuuuuuuuuu\" rel=\"nofollow\">" +
      "http://example.com/fuuuuuuuuuuuuuuuuu…</a>", message.subject
    assert_equal_html "<a href=\"http://example.com/fuuuuuuuuuuuuuuuuuuuuuuu\" rel=\"nofollow\">" +
      "…uuuuuu</a> and the overflow portion should be included in the body", message.body
  end

  test "truncating always produces a shorter subject" do
    1.upto(200) do |length|
      text = "a" * length
      message = Commits::CommitMessageHTML.new(text)
      if message.subject == text
        # No truncation occurred.
        assert_equal "", message.body
      else
        assert message.subject.length < text.length, "Expected #{message.subject.inspect} (length=#{message.subject.length}) to be shorter than #{text.inspect} (length=#{text.length})"
        refute_nil message.body
      end
    end
  end

  test "truncating never generates a 1-, 2-, or 3-character body" do
    1.upto(200) do |length|
      text = "a" * length
      message = Commits::CommitMessageHTML.new(text)
      if message.subject == text
        # No truncation occurred.
        assert_equal "", message.body
      else
        assert message.body.length >= 4, "Expected #{message.body.inspect} (length=#{message.body.length}) to be at least 4 characters long (generated from #{text.inspect} (length=#{text.length}))"
      end
    end
  end

  test "rstrips body" do
    text = " * abc \n * def\n * ghi "
    message = Commits::CommitMessageHTML.new(text)
    assert_equal " * abc", message.subject
    assert_equal " * def\n * ghi", message.body
  end

  test "handles non-standard character in url" do
    message = Commits::CommitMessageHTML.new("subject\ngo to www.gravatar.com/andsoon`")
    assert_dom_equal "go to <a href=\"http://www.gravatar.com/andsoon`\" rel=\"nofollow\">www.gravatar.com/andsoon`</a>",
      message.body
  end

  test "using the full pipeline when the message is small" do
    message = Commits::CommitMessageHTML.new("This is short.")
    assert_equal GitHub::Goomba::CommitMessagePipeline, message.commit_message_pipeline
  end

  test "using the plain text pipeline when the message is big" do
    message = Commits::CommitMessageHTML.new("a" * 52_000)
    assert_equal GitHub::Goomba::LongCommitMessagePipeline, message.commit_message_pipeline
  end

  test "handles nil commit message" do
    message = Commits::CommitMessage.new(nil)
    assert_equal "", message.message
    assert_equal "", message.subject
    assert_nil message.body
  end

  test "handles nil commit message in html" do
    message = Commits::CommitMessageHTML.new(nil)
    assert_equal "", message.message
    assert_equal "", message.subject
    assert_equal "", message.body
  end

  test "handles empty commit message" do
    message = Commits::CommitMessage.new("")
    assert_equal "", message.message
    assert_equal "", message.subject
    assert_nil message.body
  end

  test "handles empty commit message in html" do
    message = Commits::CommitMessageHTML.new("")
    assert_equal "", message.message
    assert_equal "", message.subject
    assert_equal "", message.body
  end
end
