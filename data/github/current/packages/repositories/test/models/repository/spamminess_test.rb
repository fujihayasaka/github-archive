# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class Repository::SpamminessTest < GitHub::TestCase
  fixtures do
    @pj       = create(:user, login: "pj",       plan: "medium")
    @maddox   = create(:user, login: "maddox")
    @repo = create(:repository)
  end

  setup do
    skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
    Repository.checking_for_spam = true
  end

  teardown do
    Repository.checking_for_spam = false
  end

  test "excludes spammy issues when spamminess check is enabled" do
    create(:issue, repository: @repo, title: "Visible issue", state: "open")
    spammer = create(:user, spammy: true)
    create(:issue, repository: @repo, title: "Spammy issue", state: "open", user: spammer)

    assert_equal 2, @repo.issues.count

    expected_count = GitHub.spamminess_check_enabled? ? 1 : 2
    assert_equal expected_count, @repo.open_issue_count_for(@owner)
  end

  test "doesn't add a new member if the repo is spammy" do
    spammer = create(:user, spammy: true)
    repo    = create(:repository, owner: spammer)
    assert repo.spammy?

    repo.add_member(@pj)

    assert !repo.reload.member?(@pj)
  end

  test "flags owner of repo that uses blacklisted words in their :homepage" do
    @bob = User.create(login: "bob", email: "bob@example.com", password: GitHub.default_password)
    assert !@bob.spammy?
    perform_enqueued_jobs(only: CheckForSpamJob) do
      create(:repository, owner: @bob, homepage: "http://www.getsexon.com")
    end
    assert @bob.reload.spammy?
  end

  test "repos are spammy if their owners are spammy" do
    spammy_repo = create(:repository, owner: @maddox)
    assert spammy_repo
    perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
      @maddox.mark_as_spammy
    end
    assert @maddox.spammy?
    assert spammy_repo.reload.spammy?
  end
end
