# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueCommitMessageSyntaxTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include PushTestHelper
  include ApiProgrammaticGrantHelpers

  fixtures do
    make_trusted_oauth_apps_owner
    create(:codespaces_integration)

    @user         = create(:user, email: "chris@ozmm.org", login: "user", plan: "micro")
    @forker       = create(:user, email: "forker@fork.com", login: "forker")
    @sr           = create(:user, email: "simon@rozet.name", login: "sr")
    @writer       = create(:user, email: "ymendel@pobox.com", login: "actor")
    @reader       = create(:user, email: "reader@example.com", login: "reader")
    [@user, @forker, @sr].each do |user|
      GitHub.newsies.get_and_update_settings(user) do |settings|
        settings.auto_subscribe = false
      end
    end

    @repo = create(:repository, owner: @user, name: "repo")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo)
    @repo.add_member(@writer, @user)

    @opened_issue = create :issue, repository: @repo, user: @repo.owner
    @closed_issue = create :issue, repository: @repo, user: @repo.owner,
                               state: "closed"
    @ref_issue    = create :issue, repository: @repo, user: @repo.owner,
                               number: 42
    @future_issue = create :issue, repository: @repo, user: @repo.owner,
                               number: 43,    created_at: Time.now + 1.year
    @locked_issue = create :issue, repository: @repo, user: @repo.owner,
                               number: 44
    @locked_issue.lock(@repo.owner)

    @reader_repo   = create(:repository, owner: @reader, name: "remote_repo")
    @private_repo  = create(:private_repository, owner: @user, name: "private_repo")
    @private_issue = create :issue, repository: @private_repo, user: @private_repo.owner

    @generic_author_email = "generic-author@example.com"
  end

  setup do
    example_repo :issues_and_commit_messages, @repo
    example_repo :issues_and_commit_messages, @fork
    example_repo :simple, @reader_repo

    @opened_issue.open  # ensure the issue is open

    commit_oid = @repo.heads.read("master").target_oid
    @commits = @repo.commits.history(commit_oid)
    @commits.map { |c| c.committed_date = rand(10).days.ago }
    @commit = @commits.detect { |c| c.message =~ /Closes/ }
    @generic_commit = @commits.detect { |c| c.author_email == @generic_author_email }

    @foreign_author      = { name: "Not on GitHub", email: @generic_author_email }
    @foreign_pub_commit  = make_issue_ref(@reader, @reader_repo, @opened_issue, @foreign_author)
    @foreign_priv_commit = make_issue_ref(@reader, @reader_repo, @private_issue, @foreign_author)
    @owner_pub_commit    = make_issue_ref(@reader, @reader_repo, @opened_issue, @user)
    @owner_priv_commit   = make_issue_ref(@reader, @reader_repo, @private_issue, @user)
  end

  def issues_on_push_job(before, after, repo: @opened_issue.repository, pusher: @user, ref: "refs/heads/master")
    trigger_push_event(
      repo.shard_path,
      pusher&.login,
      [[ref, before, after]],
      Time.now,
      perform_hydro_push_jobs: [HydroIssuesOnPushJob]
    )
  end

  def make_issue_ref(user, source_repo, target_issue, committer = user)
    issue_ref = "##{target_issue.number}".dup
    issue_ref.prepend("#{target_issue.repository.nwo}") if source_repo != target_issue.repository

    message  = "This is a general fix for a few issues"
    message += "\n\n"
    message += "Fixes #{issue_ref}"

    ref = source_repo.heads.read("master")
    metadata = { message: message, committer: committer }
    ref.append_commit(metadata, user) do |files|
      data = files.to_hash["issue_fix"] || "fix"
      files.add("issue_fix", "#{data} fix")
    end
  end

  test "closes issues with Closes #" do
    commit = @commits.detect { |c| c.message =~ /Closes/ }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "handles issue close from commit description (not subject)" do
    commit = @commits.detect { |c| c.author.present? && c.message =~ /closes/i && c.short_message !~ /closes/i }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes issues with Closed # syntax" do
    commit = @commits.detect { |c| c.message =~ /Closed/ }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes issues with Close # syntax" do
    commit = @commits.detect { |c| c.message =~ /Close / }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes issues with Fixes # syntax" do
    commit = @commits.detect { |c| c.message =~ /Fixes/ }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes issues with Fixed # syntax" do
    commit = @commits.detect { |c| c.message =~ /Fixed/ }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "references issues with # syntax", feature_disabled: :notifyd_enable_issue_thread_subscriptions do
    assert !@opened_issue.subscribed?(@sr)

    commit = @commits.detect { |c|  c.author_email == @sr.email }
    issue  = @ref_issue

    before, after = @repo.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "issue.events.reload.size" do
      issues_on_push_job(before, after, repo: @repo, pusher: @sr)
      assert issue.subscribed?(@sr), "sr needs to be subscribed"
    end

    assert issue.reload.open?
    events = issue.events.order("id DESC").take(2)

    # the referenced event
    assert ev = events.shift
    assert_equal "referenced", ev.event
    assert_equal commit.oid, ev.commit_id
    assert_equal @sr, ev.actor
  end

  test "cannot reference locked issues" do
    commit = @commits.detect { |c|  c.message =~ /locked issue/ }
    issue = @locked_issue

    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_no_difference "issue.events.reload.size" do
      issues_on_push_job(before, after)
    end
  end

  test "fork references issues with # syntax", feature_disabled: :notifyd_enable_issue_thread_subscriptions do
    assert !@opened_issue.subscribed?(@sr)

    commit = @commits.detect { |c|  c.author_email == @sr.email }
    issue  = @ref_issue

    before, after = @fork.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "issue.events.reload.size" do
      issues_on_push_job(before, after, repo: @fork, pusher: @forker)
      refute issue.subscribed?(@sr), "sr can't be subscribed"
    end

    assert issue.reload.open?
    events = issue.events.order("id DESC").take(2)

    # the referenced event
    assert ev = events.shift
    assert_equal "referenced", ev.event
    assert_equal commit.oid, ev.commit_id
    assert_equal @forker, ev.actor
  end

  test "references issues across forks with closes #" do
    commit_oid = @fork.heads.read("master").target_oid
    @commits = @fork.commits.history(commit_oid)
    commit = @commits.detect { |c| c.message =~ /Closes/ }
    commit.committed_date = Time.now

    before, after = @fork.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after, repo: @fork, pusher: @forker)
    end

    assert !@opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "referenced" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @repo, ev.repository
    assert_equal @fork, ev.commit_repository
  end

  test "ignores references in commits a year older than the issue" do
    commit = @commits.detect { |c| c.message =~ /#42/ }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    issues_on_push_job(before, after)
    @future_issue.reload

    assert_equal 0, @future_issue.events.size
  end

  test "references closed issues with closes #" do
    @opened_issue.close

    commit = @commits.detect { |c| c.message =~ /Closes/ }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "referenced" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "references closed issues with fixes #" do
    @opened_issue.close

    commit = @commits.detect { |c| c.message =~ /Fixes/ }
    before, after = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "referenced" }
    refute_nil ev
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "knows which commit has closed an issue" do
    commit = @commits.detect { |c| c.message =~ /Closes/ }
    after, before = @opened_issue.repository.rpc.rev_list(@commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    issues_on_push_job(before, after)

    assert @opened_issue.closed_by_commit?(commit)
    assert !@opened_issue.closed_by_commit?(@commits.first)
    assert !@closed_issue.closed_by_commit?(commit)

    issue  = @ref_issue
    assert issue.reload.open?
    assert !issue.closed_by_commit?(@commits[1])
  end

  test "closes issues in the master branch" do
    commit = @commits.detect { |c| c.message =~ /Closes/ }

    after, before = @repo.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes issues in the gh-pages branch" do
    commit = @commits.detect { |c| c.message =~ /Closes/ }

    after, before = @repo.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after, ref: "refs/heads/gh-pages")
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "doesn't close issues in non-master branch" do
    commit = @commits.detect { |c| c.message =~ /Closes/ }

    after, before = @opened_issue.repository.rpc.rev_list(@commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after, ref: "refs/heads/experimental")
    end

    assert @opened_issue.reload.open?
    assert @opened_issue.events.last.async_will_close_subject?.sync
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    assert_nil ev
  end

  test "closes locked issues" do
    commit = @commits.detect { |c| c.message =~ /Closes/ }
    owner = @opened_issue.repository.owner
    @opened_issue.lock(owner)
    assert @opened_issue.locked?

    after, before = @repo.rpc.rev_list(@commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after, ref: "refs/heads/gh-pages")
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal commit.oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "handles pending fix from commit description (not subject)" do
    commit = @commits.detect { |c| c.author.present? && c.message =~ /closes/i && c.short_message !~ /closes/i }

    after, before = @opened_issue.repository.rpc.rev_list(commit.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([commit])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after, ref: "refs/heads/experimental")
    end

    assert @opened_issue.reload.open?
    assert @opened_issue.events.last.async_will_close_subject?.sync
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    assert_nil ev
  end

  test "closes multiple issues at once" do
    other_issue = create :issue, repository: @repo, user: @repo.owner

    message  = "this is a general fix for a few issues"
    message += "\n\n"
    message += "for instance, it can fix ##{@opened_issue.number} and also fix ##{other_issue.number}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)

    issues = [@opened_issue, other_issue]
    sizes  = issues.collect { |issue|  issue.events.reload.size }
    issues_on_push_job(before, after)
    issues.zip(sizes).each do |issue, size|
      refute_equal size, issue.events.reload.size
    end

    issues.each do |issue|
      assert issue.reload.closed?
      ev = issue.events.detect { |ev| ev.event == "closed" }
      refute_nil ev
      assert !ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @user, ev.actor
    end
  end

  test "closes multiple issues at once even when the keyword is separated from the number by a newline" do
    other_issue = create :issue, repository: @repo, user: @repo.owner

    message  = "this is a general fix for a few issues"
    message += "\n\n"
    message += "for instance, it can fix ##{@opened_issue.number} and also fix"
    message += "\n"
    message += "##{other_issue.number}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)

    issues = [@opened_issue, other_issue]
    sizes  = issues.collect { |issue|  issue.events.reload.size }
    issues_on_push_job(before, after)
    issues.zip(sizes).each do |issue, size|
      refute_equal size, issue.events.reload.size
    end

    issues.each do |issue|
      assert issue.reload.closed?
      ev = issue.events.detect { |ev| ev.event == "closed" }
      refute_nil ev
      assert !ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @user, ev.actor
    end
  end

  test "closes an issue whose keyword is separated from the number by a newline" do
    message  = "this fixes an issue"
    message += "\n\n"
    message += "it will fix"
    message += "\n"
    message += "##{@opened_issue.number}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes an issue whose keyword is separated from the number by extra whitespace" do
    message  = "this fixes   ##{@opened_issue.number}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes an issue whose keyword is separated from the number by a newline and extra whitespace" do
    message  = "this fixes an issue"
    message += "\n\n"
    message += "it will fix  "
    message += "\n"
    message += "##{@opened_issue.number}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes an issue whose keyword is followed by a colon" do
    message  = "this fixes an issue"
    message += "\n\n"
    message += "it will fix: ##{@opened_issue.number}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes a full-url issue" do
    url = "#{GitHub.url}/#{@opened_issue.repository.name_with_owner}/issues/#{@opened_issue.number}"
    message = "this will fix #{url}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes a full-url issue using pull URL" do
    url = "#{GitHub.url}/#{@opened_issue.repository.name_with_owner}/pull/#{@opened_issue.number}"
    message = "this will close #{url}, for that PR has been superseded"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes a full-url issue in commit description" do
    url = "#{GitHub.url}/#{@opened_issue.repository.name_with_owner}/issues/#{@opened_issue.number}"
    message  = "this is a thing"
    message += "\n\n"
    message += "it will fix #{url}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "closes a full-url issue in commit description using colon" do
    url = "#{GitHub.url}/#{@opened_issue.repository.name_with_owner}/issues/#{@opened_issue.number}"
    message  = "this is a thing"
    message += "\n\n"
    message += "it will fix: #{url}"

    ref = @repo.heads.read("master")
    metadata = { message: message, committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.closed?
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    refute_nil ev
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    assert_equal @user, ev.actor
  end

  test "doesn't let keyword-ending words close issues" do
    ref = @repo.heads.read("master")
    metadata = { message: "affix ##{@opened_issue.number}", committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @opened_issue.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    assert_difference "@opened_issue.events.reload.size" do
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.open?
    assert !@opened_issue.events.last.async_will_close_subject?.sync
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    assert_nil ev

    ref = @repo.heads.read("master")
    metadata = { message: "disclose ##{@opened_issue.number}", committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    assert_difference "@opened_issue.events.reload.size" do
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])
      issues_on_push_job(before, after)
    end

    assert @opened_issue.reload.open?
    assert !@opened_issue.events.last.async_will_close_subject?.sync
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    assert_nil ev
  end

  test "correctly determines pending fix status when multiple issues are referenced" do
    other_issue = create(:issue, repository: @repo)
    issues = [@opened_issue, other_issue]
    master_oid = @repo.heads.read("master").target_oid

    ref = @repo.heads.create("both-pending", master_oid, @user)
    metadata = { message: "fixes ##{@opened_issue.number} and also will fix ##{other_issue.number}", committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    after, before = @repo.repository.rpc.rev_list(ref.target.oid).take(2)
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

    sizes  = issues.collect { |i|  i.events.reload.size }
    issues_on_push_job(before, after, repo: @repo, ref: "refs/heads/both-pending")
    issues.zip(sizes).each do |issue, size|
      refute_equal size, issue.events.reload.size
    end

    issues.each do |issue|
      assert issue.reload.open?
      ev = issue.events.last
      assert ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      ev = issue.events.detect { |ev| ev.event == "closed" }
      assert_nil ev
    end

    ref = @repo.heads.create("neither-pending", master_oid, @user)
    metadata = { message: "refs ##{@opened_issue.number} and also ##{other_issue.number}", committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    sizes = issues.collect { |i|  i.events.reload.size }
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])
    issues_on_push_job(before, after, repo: @repo, ref: "refs/heads/neither-pending")
    issues.zip(sizes).each do |issue, size|
      refute_equal size, issue.events.reload.size
    end

    issues.each do |issue|
      assert issue.reload.open?
      ev = issue.events.last
      assert !ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      ev = issue.events.detect { |ev| ev.event == "closed" }
      assert_nil ev
    end

    ref = @repo.heads.create("first-pending", master_oid, @user)
    metadata = { message: "fixes ##{@opened_issue.number} and also refs ##{other_issue.number}", committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    sizes = issues.collect { |i|  i.events.reload.size }
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])
    issues_on_push_job(before, after, repo: @repo, ref: "refs/heads/first-pending")
    issues.zip(sizes).each do |issue, size|
      refute_equal size, issue.events.reload.size
    end

    assert @opened_issue.reload.open?
    ev = @opened_issue.events.last
    assert ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    assert_nil ev

    assert other_issue.reload.open?
    ev = other_issue.events.last
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    ev = other_issue.events.detect { |ev| ev.event == "closed" }
    assert_nil ev

    ref = @repo.heads.create("last-pending", master_oid, @user)
    metadata = { message: "refs ##{@opened_issue.number} and also will fix ##{other_issue.number}", committer: @user }
    ref.append_commit(metadata, @user) do |files|
      files.add("something", "fixedit")
    end

    sizes = issues.collect { |i|  i.events.reload.size }
    Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])
    issues_on_push_job(before, after, repo: @repo, ref: "refs/heads/last-pending")
    issues.zip(sizes).each do |issue, size|
      refute_equal size, issue.events.reload.size
    end

    assert @opened_issue.reload.open?
    ev = @opened_issue.events.last
    assert !ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
    assert_nil ev

    assert other_issue.reload.open?
    ev = other_issue.events.last
    assert ev.async_will_close_subject?.sync
    assert_equal ref.target_oid, ev.commit_id
    ev = other_issue.events.detect { |ev| ev.event == "closed" }
    assert_nil ev
  end

  context "cross-repo mentions" do
    test "can be a pending fix" do
      user = create(:user)
      @new_repo = create(:repository, owner: user, from_example: :issues_and_commit_messages)

      master_oid = @new_repo.heads.read("master").target_oid
      ref = @new_repo.heads.create("whatever", master_oid, user)
      metadata = { message: "fix #{@repo.name_with_owner}##{@opened_issue.number}", committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@opened_issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_repo, pusher: user, ref: "refs/heads/whatever")
      end

      assert @opened_issue.reload.open?
      ev = @opened_issue.events.last
      refute_nil ev
      assert ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_repo.id, ev.commit_repository_id
      ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
      assert_nil ev
    end

    test "can close an issue" do
      user = create(:user)
      @new_repo = create(:repository, owner: user, from_example: :issues_and_commit_messages)

      @repo.add_member(user)

      ref = @new_repo.heads.read("master")
      metadata = { message: "fix #{@repo.name_with_owner}##{@opened_issue.number}", committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@opened_issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_repo, pusher: user)
      end

      assert @opened_issue.reload.closed?
      ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
      refute_nil ev
      assert !ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_repo.id, ev.commit_repository_id
      assert_equal user, ev.actor
    end

    test "can close an issue whose keyword is separated from the issue by a newline" do
      user = create(:user)
      @new_repo = create(:repository, owner: user, from_example: :issues_and_commit_messages)

      @repo.add_member(user)

      message  = "this is a fix"
      message += "\n\n"
      message += "this will fix"
      message += "\n"
      message += "#{@repo.name_with_owner}##{@opened_issue.number}"

      ref = @new_repo.heads.read("master")
      metadata = { message: message, committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@opened_issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_repo.repository, pusher: user)
      end

      assert @opened_issue.reload.closed?
      ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
      refute_nil ev
      assert !ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_repo.id, ev.commit_repository_id
      assert_equal user, ev.actor
    end

    test "can close an issue whose keyword is separated from the issue by extra whitespace" do
      user = create(:user)
      @new_repo = create(:repository, owner: user, from_example: :issues_and_commit_messages)

      @repo.add_member(user)

      message = "this will fix   #{@repo.name_with_owner}##{@opened_issue.number}"

      ref = @new_repo.heads.read("master")
      metadata = { message: message, committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@opened_issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_repo, pusher: user)
      end

      assert @opened_issue.reload.closed?
      ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
      refute_nil ev
      assert !ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_repo.id, ev.commit_repository_id
      assert_equal user, ev.actor
    end

    test "can close an issue whose keyword is separated from the issue by a newline and extra whitespace" do
      user = create(:user)
      @new_repo = create(:repository, owner: user, from_example: :issues_and_commit_messages)

      @repo.add_member(user)

      message  = "this is a fix"
      message += "\n\n"
      message += "this will fix  "
      message += "\n"
      message += "#{@repo.name_with_owner}##{@opened_issue.number}"

      ref = @new_repo.heads.read("master")
      metadata = { message: message, committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@opened_issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_repo.repository, pusher: user)
      end

      assert @opened_issue.reload.closed?
      ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
      refute_nil ev
      assert !ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_repo.id, ev.commit_repository_id
      assert_equal user, ev.actor
    end

    test "needs write access to close an issue" do
      user = create(:user)
      @new_repo = create(:repository, owner: user, from_example: :issues_and_commit_messages)

      ref = @new_repo.heads.read("master")
      metadata = { message: "fix #{@repo.name_with_owner}##{@opened_issue.number}", committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@opened_issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_repo, pusher: user)
      end

      assert @opened_issue.reload.open?
      ev = @opened_issue.events.last
      refute_nil ev
      assert ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_repo.id, ev.commit_repository_id
      ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
      assert_nil ev
    end

    test "can go from private repo to another private repo in an org" do
      org  = create :organization, plan: "bronze"
      user = create(:user)
      org.add_admin(user)

      @repo     = create(:private_repository, owner: org)
      @issue    = create(:issue, repository: @repo, user: user)

      @new_repo = create(:private_repository, owner: org, from_example: :issues_and_commit_messages)

      master_oid = @new_repo.heads.read("master").target_oid
      ref = @new_repo.heads.create("whatever", master_oid, user)
      metadata = { message: "#{@repo.name_with_owner}##{@issue.number} is pretty interesting", committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_repo, pusher: user, ref: "refs/heads/whatever")
      end

      ev = @issue.events.last
      refute_nil ev
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_repo.id, ev.commit_repository_id
    end

    test "can go from private repo to another private repo in an org when committer is not a user" do
      org  = create :organization, plan: "bronze"
      user = create(:user)
      org.add_admin(user)

      @repo     = create(:private_repository, owner: org)
      @issue    = create(:issue, repository: @repo, user: user)

      @new_repo = create(:private_repository, owner: org, from_example: :issues_and_commit_messages)

      master_oid = @new_repo.heads.read("master").target_oid
      ref = @new_repo.heads.create("whatever", master_oid, user)
      metadata = {
        message: "#{@repo.name_with_owner}##{@issue.number} is pretty interesting",
        committer: { name: "SomeOne McNoName", email: "someone@someplace.org" },
      }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_repo, pusher: user, ref: "refs/heads/whatever")
      end

      ev = @issue.events.last
      refute_nil ev
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_repo.id, ev.commit_repository_id
    end

    context "when pusher is using a codespaces token" do
      test "does not close an issue in another private repo" do
        new_repo = create(:repository, owner: @user, from_example: :issues_and_commit_messages)

        ref = new_repo.heads.read("master")
        metadata = { message: "fix #{@repo.name_with_owner}##{@opened_issue.number}", committer: @user }
        ref.append_commit(metadata, @user) do |files|
          files.add("something", "fixedit")
        end

        session = create(:user_session, user: @user)
        codespace = create(:codespace,
          owner: @user,
          name: "user-codespace",
          repository: new_repo)
        Codespaces::Tokens.mint_github_token(@user, codespace)
        oauth_access = OauthAccess.last

        after, before = new_repo.repository.rpc.rev_list(ref.target.oid).take(2)
        message = {
          repository_id:  new_repo.repository.id,
          ref_updates: [{ ref: "refs/heads/master", before: before, after: after }],
          pushed_at: Time.now,
          pusher: @user.login,
          oauth_access_id: T.must(oauth_access).id
        }
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")

        @opened_issue.reload
        assert_predicate @opened_issue, :open?

        assert ev = @opened_issue.events.last
        assert_equal "referenced", ev.event
      end
    end
  end

  context "cross-repo mentions from a fork" do
    test "can be a pending fix" do
      user = create(:user)
      @new_fork = create(:fork_repository, forker: user, fork_repo: @repo, from_example: :issues_and_commit_messages)

      master_oid = @new_fork.heads.read("master").target_oid
      ref = @new_fork.heads.create("whatever", master_oid, user)
      metadata = { message: "fix #{@repo.name_with_owner}##{@opened_issue.number}", committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_fork.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@opened_issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_fork, pusher: user, ref: "refs/heads/whatever")
      end

      assert @opened_issue.reload.open?
      ev = @opened_issue.events.last
      refute_nil ev
      assert ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_fork.id, ev.commit_repository_id
      ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
      assert_nil ev
    end

    test "cannot close an issue" do
      user = create(:user)
      @new_fork = create(:fork_repository, forker: user, fork_repo: @repo, from_example: :issues_and_commit_messages)

      @repo.add_member(user)

      ref = @new_fork.heads.read("master")
      metadata = { message: "fix #{@repo.name_with_owner}##{@opened_issue.number}", committer: user }
      ref.append_commit(metadata, user) do |files|
        files.add("something", "fixedit")
      end

      after, before = @new_fork.repository.rpc.rev_list(ref.target.oid).take(2)
      Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([ref.target])

      assert_difference "@opened_issue.events.reload.size" do
        issues_on_push_job(before, after, repo: @new_fork, pusher: user)
      end

      ev = @opened_issue.events.last
      refute_nil ev
      assert ev.async_will_close_subject?.sync
      assert_equal ref.target_oid, ev.commit_id
      assert_equal @new_fork.id, ev.commit_repository_id
      ev = @opened_issue.events.detect { |ev| ev.event == "closed" }
      assert_nil ev
    end
  end

  context "when commit author/committer belongs to a user with write access" do
    context "and pusher has write access" do
      test "creates reference" do
        after, before = @repo.rpc.rev_list(@commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@commit])

        assert_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @repo, pusher: @writer, ref: "refs/heads/experimental")
        end

        refute @opened_issue.reload.closed?

        assert ev = @opened_issue.events.last
        assert ev.async_will_close_subject?.sync
        assert_equal "referenced", ev.event
        assert_equal @commit.oid, ev.commit_id
        assert_equal @writer, ev.actor
      end

      test "closes issue" do
        after, before = @repo.rpc.rev_list(@commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@commit])

        assert_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @repo, pusher: @writer)
        end

        assert @opened_issue.reload.closed?

        assert ev = @opened_issue.events.last
        refute ev.async_will_close_subject?.sync
        assert_equal "closed", ev.event
        assert_equal @commit.oid, ev.commit_id
        assert_equal @writer, ev.actor
      end
    end

    context "and pusher has read access" do
      test "creates reference" do
        after, before = @reader_repo.rpc.rev_list(@owner_pub_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@owner_pub_commit])

        assert_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @reader_repo, pusher: @reader, ref: "refs/heads/experimental")
        end

        refute @opened_issue.reload.closed?

        assert ev = @opened_issue.events.last
        assert ev.async_will_close_subject?.sync
        assert_equal "referenced", ev.event
        assert_equal @owner_pub_commit.oid, ev.commit_id
        assert_equal @reader, ev.actor
      end

      test "does not close issue" do
        after, before = @reader_repo.rpc.rev_list(@owner_pub_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@owner_pub_commit])

        assert_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @reader_repo, pusher: @reader)
        end

        refute @opened_issue.reload.closed?

        assert ev = @opened_issue.events.last
        assert ev.async_will_close_subject?.sync
        assert_equal "referenced", ev.event
        assert_equal @owner_pub_commit.oid, ev.commit_id
        assert_equal @reader, ev.actor
      end
    end

    context "and pusher has no access" do
      test "does not create reference" do
        after, before = @reader_repo.repository.rpc.rev_list(@owner_priv_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@owner_priv_commit])

        assert_no_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @reader_repo.repository, pusher: @reader, ref: "refs/heads/experimental")
        end

        refute @opened_issue.reload.closed?
        assert @opened_issue.events.empty?
      end

      test "does not close issue" do
        after, before = @reader_repo.repository.rpc.rev_list(@owner_priv_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@owner_priv_commit])

        assert_no_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @reader_repo.repository, pusher: @reader)
        end

        refute @opened_issue.reload.closed?
        assert @opened_issue.events.empty?
      end
    end

    context "and pusher is nil" do
      test "does not create reference or close issue" do
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@commit])

        after, before = @reader_repo.repository.rpc.rev_list(@owner_priv_commit.oid).take(2)
        assert_no_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @repo, pusher: nil, ref: "refs/heads/experimental")
        end

        refute @opened_issue.reload.closed?
        assert @opened_issue.events.empty?
      end
    end
  end

  context "when commit author/committer belongs to a user with no access" do
    context "and pusher has write access" do
      test "creates reference" do
        after, before = @repo.rpc.rev_list(@generic_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@generic_commit])

        assert_difference "@ref_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @repo, pusher: @writer, ref: "refs/heads/experimental")
        end

        refute @ref_issue.reload.closed?

        assert ev = @ref_issue.events.last
        assert ev.async_will_close_subject?.sync
        assert_equal "referenced", ev.event
        assert_equal @generic_commit.oid, ev.commit_id
        assert_equal @writer, ev.actor
      end

      test "closes issue" do
        after, before = @repo.rpc.rev_list(@generic_commit.oid).take(2)

        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@generic_commit])

        assert_difference "@ref_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @repo, pusher: @writer)
        end

        assert @ref_issue.reload.closed?

        assert ev = @ref_issue.events.last
        refute ev.async_will_close_subject?.sync
        assert_equal "closed", ev.event
        assert_equal @generic_commit.oid, ev.commit_id
        assert_equal @writer, ev.actor
      end
    end

    context "and pusher has read access" do
      test "creates reference" do
        after, before = @reader_repo.rpc.rev_list(@foreign_pub_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@foreign_pub_commit])

        assert_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @reader_repo, pusher: @reader, ref: "refs/heads/experimental")
        end

        refute @opened_issue.reload.closed?

        assert ev = @opened_issue.events.last
        assert ev.async_will_close_subject?.sync
        assert_equal "referenced", ev.event
        assert_equal @foreign_pub_commit.oid, ev.commit_id
        assert_equal @reader, ev.actor
      end

      test "does not close issue" do
        after, before = @reader_repo.rpc.rev_list(@foreign_pub_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@foreign_pub_commit])

        assert_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @reader_repo, pusher: @reader)
        end

        refute @opened_issue.reload.closed?

        assert ev = @opened_issue.events.last
        assert ev.async_will_close_subject?.sync
        assert_equal "referenced", ev.event
        assert_equal @foreign_pub_commit.oid, ev.commit_id
        assert_equal @reader, ev.actor
      end
    end

    context "and pusher has no access" do
      test "does not create reference" do
        after, before = @reader_repo.repository.rpc.rev_list(@foreign_priv_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@foreign_priv_commit])

        assert_no_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @reader_repo.repository, pusher: @reader, ref: "refs/heads/experimental")
        end

        refute @opened_issue.reload.closed?
        assert @opened_issue.events.empty?
      end

      test "does not close issue" do
        after, before = @reader_repo.repository.rpc.rev_list(@foreign_priv_commit.oid).take(2)
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@foreign_priv_commit])

        assert_no_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @reader_repo.repository, pusher: @reader)
        end

        refute @opened_issue.reload.closed?
        assert @opened_issue.events.empty?
      end
    end

    context "and pusher is nil" do
      test "does not create reference or close issue" do
        Repositories::RefUpdate.any_instance.stubs(:commits_pushed).returns([@commit])

        after, before = @reader_repo.repository.rpc.rev_list(@owner_priv_commit.oid).take(2)
        assert_no_difference "@opened_issue.events.reload.size" do
          issues_on_push_job(before, after, repo: @repo, pusher: nil, ref: "refs/heads/experimental")
        end

        refute @opened_issue.reload.closed?
        assert @opened_issue.events.empty?
      end
    end
  end
end
