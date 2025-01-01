# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestFromEmuWithSquashMergeTest < GitHub::TestCase
  test "EMU authors don't get cited as co-authors of their own commits", skip_enterprise: true do
    # As seen in https://github.com/github/pull-requests/issues/4775,
    # a commit may be made by "user@example.com", but if they're an EMU, we
    # store their email _internally_ as "user+enterprise@example.com", so we
    # have to be careful when distinguishing authors and co-authors.
    emu = create(:emu)
    emu_business = emu.enterprise_managed_business
    email_with_shortcode = emu.emails.first.email
    email_without_shortcode = emu.remove_shortcode(email_with_shortcode)

    assert_includes email_with_shortcode, "+#{emu_business.shortcode}@"
    refute_includes email_without_shortcode, "+#{emu_business.shortcode}@"

    source = create(:repository, owner: emu, from_example: :pull_request_fork)
    issue = create(:issue, user: emu, repository: source, body: "some change")
    base_ref = source.heads.find("master")
    base_sha = base_ref.sha
    head_ref = source.heads.create("stuff", base_ref.target_oid, emu)

    # 1. EMU author of commit does not show up as co-author.
    head_sha = source.rpc.create_tree_changes(base_sha, {
      "message" => "docs: add stuff",
      "committer" => {
        "email" => email_without_shortcode,
        "name" => emu.name,
        "time" => emu.time_zone.now.iso8601,
      },
    }, { "STUFF.md" => "stuff\n" })
    head_ref.set_target_object(head_sha)
    pull = PullRequest.new(
      repository: source,
      base_repository: source,
      base_user: source.owner,
      base_ref: "master",
      base_sha: base_sha,
      head_user: emu,
      head_repository: source,
      head_ref: "stuff",
      head_sha: head_sha,
      issue: issue,
      user: emu
    )

    assert_equal 1, pull.changed_commits.size
    refute_includes pull.default_squash_commit_message, "Co-authored-by:"

    # 2. Unrelated committer _does_ show up as co-author.
    head_sha = source.rpc.create_tree_changes(head_sha, {
      "message" => "docs: add more stuff",
      "committer" => {
        "email" => "wincent@github.com",
        "name" => "Greg Hurrell",
        "time" => emu.time_zone.now.iso8601,
      },
    }, { "MORE_STUFF.md" => "stuff\n" })
    head_ref.set_target_object(pull.head_sha)

    # Recreate the pull to circumvent memoization.
    pull = PullRequest.new(
      repository: source,
      base_repository: source,
      base_user: source.owner,
      base_ref: "master",
      base_sha: base_sha,
      head_user: emu,
      head_repository: source,
      head_ref: "stuff",
      head_sha: head_sha,
      issue: issue,
      user: emu
    )

    assert_equal 2, pull.changed_commits.size
    assert_includes pull.default_squash_commit_message, "Co-authored-by: Greg Hurrell <wincent@github.com>"
    refute_includes pull.default_squash_commit_message, email_with_shortcode
    refute_includes pull.default_squash_commit_message, email_without_shortcode

    # 3. We don't skip over "shortcode" email addresses arbitrarily, only ones
    # which correspond to the associated enterprise user.
    head_sha = source.rpc.create_tree_changes(head_sha, {
      "message" => "docs: add even more stuff",
      "committer" => {
        "email" => "wincent+twin@github.com",
        "name" => "Twin Brother",
        "time" => emu.time_zone.now.iso8601,
      },
    }, { "EVEN_MORE_STUFF.md" => "stuff\n" })
    head_ref.set_target_object(pull.head_sha)

    # Recreate the pull to circumvent memoization.
    pull = PullRequest.new(
      repository: source,
      base_repository: source,
      base_user: source.owner,
      base_ref: "master",
      base_sha: base_sha,
      head_user: emu,
      head_repository: source,
      head_ref: "stuff",
      head_sha: head_sha,
      issue: issue,
      user: emu
    )

    assert_equal 3, pull.changed_commits.size
    assert_includes pull.default_squash_commit_message, "Co-authored-by: Greg Hurrell <wincent@github.com>"
    assert_includes pull.default_squash_commit_message, "Co-authored-by: Twin Brother <wincent+twin@github.com>"
    refute_includes pull.default_squash_commit_message, email_with_shortcode
    refute_includes pull.default_squash_commit_message, email_without_shortcode
  end
end
