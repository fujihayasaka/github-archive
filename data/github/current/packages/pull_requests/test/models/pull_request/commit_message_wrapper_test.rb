# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitMessageWrapperTest < GitHub::TestCase

  test "it wraps text to fit 72 chars per Git convention" do
    commit_message = <<~COMMIT_MESSAGE
    Git paths have no inherent encoding, they are opaque binary strings that can be in any encoding. The macro `rb_str_new_utf8` is used in places to convert raw C strings representing paths (and other things) into ruby strings tagged with UTF8 encoding.

    This is not safe, since the macro simply copies bytes and tags the string with the specified encoding; it does not do any validity checking or transcoding. Thus it can easily create an invalid string (i.e. one for which `String#valid_encoding?` is false) if the repo contains files whose paths are multibyte strings in encodings other than UTF8. These strings are poisoned and difficult to work with: they can't be compared safely because of the semantics of ruby strings and they often can't be concatenated to a larger output buffer for display (which will attempt to transcode to the output buffer's native encoding, usually UTF8). The comparison issue hit us a few times at GitHub.
    COMMIT_MESSAGE

    expected = <<~MESSAGE
    Git paths have no inherent encoding, they are opaque binary strings that
    can be in any encoding. The macro `rb_str_new_utf8` is used in places to
    convert raw C strings representing paths (and other things) into ruby
    strings tagged with UTF8 encoding.

    This is not safe, since the macro simply copies bytes and tags the
    string with the specified encoding; it does not do any validity checking
    or transcoding. Thus it can easily create an invalid string (i.e. one
    for which `String#valid_encoding?` is false) if the repo contains files
    whose paths are multibyte strings in encodings other than UTF8. These
    strings are poisoned and difficult to work with: they can't be compared
    safely because of the semantics of ruby strings and they often can't be
    concatenated to a larger output buffer for display (which will attempt
    to transcode to the output buffer's native encoding, usually UTF8). The
    comparison issue hit us a few times at GitHub.
    MESSAGE

    actual = PullRequest::CommitMessageWrapper.new(commit_message).wrap
    assert_equal expected.chomp, actual
  end

  test "it handles words correctly that are over 72 chars" do
    long_word = <<~COMMIT_MESSAGE
    here is an example of a long url: https://www.url.com/some/very/long/url/that/easily/exceeds/72/characters/per/line/more/202000202/test/length/1822304
    COMMIT_MESSAGE

    expected = <<~MESSAGE
    here is an example of a long url:
    https://www.url.com/some/very/long/url/that/easily/exceeds/72/characters/per/line/more/202000202/test/length/1822304
    MESSAGE

    actual = PullRequest::CommitMessageWrapper.new(long_word).wrap
    assert_equal expected.chomp, actual
  end

  test "it handles bullets correctly" do
    bulleted_message = <<~COMMIT_MESSAGE
    Find command: make matching case insensitive

    A case insensitive find is more user-friendly because users cannot be expected to remember the exact case of the keywords.

    Let's,
    - update the search algorithm to use case-insensitive matching
    -  add a script to migrate stress tests to the new format this is a longer bullet and is over the characters per line
    COMMIT_MESSAGE

    expected  = <<~MESSAGE
    Find command: make matching case insensitive

    A case insensitive find is more user-friendly because users cannot be
    expected to remember the exact case of the keywords.

    Let's,
    - update the search algorithm to use case-insensitive matching
    - add a script to migrate stress tests to the new format this is a
    longer bullet and is over the characters per line
    MESSAGE

    actual = PullRequest::CommitMessageWrapper.new(bulleted_message).wrap
    assert_equal expected.chomp, actual
  end
end
