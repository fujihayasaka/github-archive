# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class CheckSuites::PublicTest < Api::TestCase
  include PushTestHelper

  fixtures do
    @org_admin    = create :paid_user, login: "octocat"
    @org          = create :organization, admin: @org_admin, login: "github"
    @repository   = create :private_repository, owner: @org, name: "Hello-World", from_example: :simple
  end

  context "SkipChecksTest" do
    test "returns true if the last commit sets skip-checks as true" do
      @message = <<~MSG
        OK, now we're ready

        skip-checks: true
      MSG

      ref = @repository.heads.find("master")
      before = ref.target_oid
      commit = ref.append_commit({ message: @message, committer: @org_admin }, @org_admin) do |files|
        files.add("blah.txt", "some contents")
      end

      push_attrs = {
        before: before,
        after: commit.sha,
        ref: "refs/heads/master",
        repository_id: @repository.id,
        pusher_id: @org_admin.id,
        pushed_at: Time.now,
      }

      @commit = @repository.refs["master"].commit
      push = create :repositories_push, push_attrs

      assert CheckSuites::Public.skip_checks_for_push?(push: push)
    end

    test "returns false if the last commit did not set skip-checks as true" do
      push = push_changes(repository: @repository, changes: { path: "README", content: "new stuff" })

      refute CheckSuites::Public.skip_checks_for_push?(push: push)
    end

    test "returns false if the last commit is bad" do
      bad_oid = Sham.sha
      empty_oid = "0" * 40

      push_attrs = {
        before: empty_oid,
        after: bad_oid,
        ref: "refs/heads/my-branch",
        repository_id: @repository.id,
        pusher_id: @org_admin.id,
        pushed_at: Time.now,
      }
      push = create :repositories_push, push_attrs

      refute CheckSuites::Public.skip_checks_for_push?(push: push)
    end
  end

  context "RequestChecksTest" do
    test "returns true if the last commit sets request-checks as true" do
      @message = <<~MSG
        OK, now we're ready

        request-checks: true
      MSG

      ref = @repository.heads.find("master")
      before = ref.target_oid
      commit = ref.append_commit({ message: @message, committer: @org_admin }, @org_admin) do |files|
        files.add("blah.txt", "some contents")
      end

      push_attrs = {
        before: before,
        after: commit.sha,
        ref: "refs/heads/master",
        repository_id: @repository.id,
        pusher_id: @org_admin.id,
        pushed_at: Time.now,
      }

      @commit = @repository.refs["master"].commit
      push = create :repositories_push, push_attrs

      assert CheckSuites::Public.request_checks_for_push?(push: push)
    end

    test "returns false if the last commit did not set request-checks as true" do
      push = push_changes(repository: @repository, changes: { path: "README", content: "new stuff" })

      refute CheckSuites::Public.request_checks_for_push?(push: push)
    end

    test "returns false if the last commit is bad" do
      bad_oid = Sham.sha
      empty_oid = "0" * 40

      push_attrs = {
        before: empty_oid,
        after: bad_oid,
        ref: "refs/heads/my-branch",
        repository_id: @repository.id,
        pusher_id: @org_admin.id,
        pushed_at: Time.now,
      }
      push = create :repositories_push, push_attrs

      refute CheckSuites::Public.request_checks_for_push?(push: push)
    end
  end
end
