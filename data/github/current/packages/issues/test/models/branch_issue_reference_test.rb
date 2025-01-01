# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests_controller_test_helper"

class BranchIssueReferenceTest < GitHub::TestCase

  include PullRequestsControllerTestHelper

  context ".by_issue scope" do
    test "includes only references for the given issue" do
      user = create(:user)
      issue = create(:issue, user: user)
      other_issue = create(:issue, user: user)

      reference = create(:branch_issue_reference, issue: issue)
      other_reference = create(:branch_issue_reference, issue: other_issue)

      result = BranchIssueReference.by_issue(issue)

      assert_includes result, reference
      refute_includes result, other_reference
    end
  end

  context ".by_branch_name scope" do
    test "includes only references for the given branch" do
      user = create(:user)
      issue = create(:issue, user: user)

      reference = create(:branch_issue_reference, issue: issue, branch_name: "found")
      other_reference = create(:branch_issue_reference, issue: issue, branch_name: "not-found")

      result = BranchIssueReference.by_branch_name("found")

      assert_includes result, reference
      refute_includes result, other_reference
    end
  end

  context ".by_user scope" do
    test "includes only references where the branch issue reference was created by the given user" do
      user = create(:user)
      issue = create(:issue, user: user)
      other_user = create(:user)

      ref1 = create(:branch_issue_reference, issue: issue, creator_id: user.id)
      ref2 = create(:branch_issue_reference, issue: issue, creator_id: other_user.id)

      result = BranchIssueReference.by_user(user)

      assert_includes result, ref1
      refute_includes result, ref2
    end
  end

  context "validations" do
    test "requires creator" do
      ref = BranchIssueReference.new
      refute_predicate ref, :valid?
      assert_includes ref.errors[:creator], "can't be blank"
    end

    test "requires issue" do
      ref = BranchIssueReference.new
      refute_predicate ref, :valid?
      assert_includes ref.errors[:issue], "can't be blank"
    end

    test "requires branch name" do
      ref = BranchIssueReference.new
      refute_predicate ref, :valid?
      assert_includes ref.errors[:branch_name], "can't be blank"
    end

    test "sets issue repository to match issue" do
      issue = create(:issue)
      ref = BranchIssueReference.new(issue: issue)

      ref.valid?

      assert_equal issue.repository, ref.issue_repository
    end

    test "requires a unique issue + repo + branch name" do
      issue = create(:issue)
      repo = create(:repository)
      ref1 = create(:branch_issue_reference, issue: issue, branch_repository: repo, branch_name: "issue-1")
      ref2 = build(:branch_issue_reference, creator: issue.user, issue: issue, branch_repository: repo, branch_name: "issue-1")
      refute_predicate ref2, :valid?
      assert_includes ref2.errors[:branch_name], "has already been taken"
    end

    test "allows an issue to have the same branch name in different repos" do
      issue = create(:issue)
      ref1 = create(:branch_issue_reference, issue: issue, branch_repository: create(:repository), branch_name: "issue-1")
      ref2 = build(:branch_issue_reference, creator: issue.user, issue: issue, branch_repository: create(:repository), branch_name: "issue-1")
      assert_predicate ref2, :valid?
    end

    test "allows a branch to reference to different issues" do
      repo = create(:repository)
      issue1 = create(:issue, repository: repo)
      issue2 = create(:issue, repository: repo)
      ref1 = create(:branch_issue_reference, issue: issue1, branch_repository: repo, branch_name: "issue-1")
      ref2 = build(:branch_issue_reference, issue: issue2, creator: issue2.user, branch_repository: repo, branch_name: "issue-1")
      assert_predicate ref2, :valid?
    end
  end

  # These tests are exclusively mocking out the underlying methods on the issue
  # and repository. Setting up the repository states and permissions didn't seem worth
  # the return on investment
  context ".creatable_for?" do
    test "false if the issue repo is not writable by the user" do
      user = build(:user)
      repository = build(:repository)
      issue = build(:issue, user: user, repository: repository)

      repository.stubs(:writable_by?).with(user).returns(false)

      refute BranchIssueReference.creatable_for?(user: user, issue: issue, repository: repository)
    end

    test "false if the user has permission to write but the repo is empty" do
      user = build(:user)
      repository = build(:repository)
      issue = build(:issue, user: user, repository: repository)

      repository.stubs(:writable_by?).with(user).returns(true)
      repository.stubs(:empty?).returns(true)

      refute BranchIssueReference.creatable_for?(user: user, issue: issue, repository: repository)
    end

    test "false if the repo is not currently in a writable state" do
      user = build(:user)
      repository = build(:repository)
      issue = build(:issue, user: user, repository: repository)

      repository.stubs(:writable_by?).with(user).returns(true)
      repository.stubs(:empty?).returns(false)
      repository.stubs(:writable?).returns(false)

      refute BranchIssueReference.creatable_for?(user: user, issue: issue, repository: repository)
    end

    test "true if all of those things are true" do
      user = build(:user)
      repository = build(:repository)
      issue = build(:issue, user: user, repository: repository)

      repository.stubs(:writable_by?).with(user).returns(true)
      repository.stubs(:empty?).returns(false)
      repository.stubs(:writable?).returns(true)

      assert BranchIssueReference.creatable_for?(user: user, issue: issue, repository: repository)
    end

    test "false if the issue is a Pull Request" do
      user = create(:user)
      repository = create(:repository)
      issue = build(:issue, user: user, repository: repository)

      repository.stubs(:writable_by?).with(user).returns(true)
      repository.stubs(:empty?).returns(false)
      repository.stubs(:writable?).returns(true)

      # stub the predicate to avoid having to persist the repo, user, issue, and PR
      issue.stubs(:pull_request?).returns(true)

      refute BranchIssueReference.creatable_for?(user: user, issue: issue, repository: repository)
    end
  end

  context ".link_pull_request" do
    test "creates a close issue reference if a branch issue reference exists" do
      @source_owner = create(:user, login: "ari", plan: "large")
      repo, pull, _ = make_repo_and_pull_with_branch(@source_owner, "topic", pull: true)
      # Work around the way the helper method invokes the pull_request factory. It takes the user
      # from an internally generated issue
      pull.update!(user: @source_owner)
      issue = create(:issue, user: @source_owner, repository: repo)
      create(:branch_issue_reference, issue: issue, branch_name: "topic", creator: @source_owner)

      BranchIssueReference.link_pull_request(pull)

      assert CloseIssueReference.closes(issue).by_user(@source_owner).exists?
    end

    test "deletes the existing branch issue reference" do
      @source_owner = create(:user, login: "ari", plan: "large")
      repo, pull, _ = make_repo_and_pull_with_branch(@source_owner, "topic", pull: true)
      # Work around the way the helper method invokes the pull_request factory. It takes the user
      # from an internally generated issue
      pull.update!(user: @source_owner)
      issue = create(:issue, user: @source_owner, repository: repo)
      create(:branch_issue_reference, issue: issue, branch_name: "topic", creator: @source_owner)

      BranchIssueReference.link_pull_request(pull)

      refute BranchIssueReference.by_repo_and_branch(repo, "topic")
    end

    test "deletes existing branch_issue_reference if close_issue_reference already exists" do
      @source_owner = create(:user, login: "ari", plan: "large")
      repo, pull, _ = make_repo_and_pull_with_branch(@source_owner, "topic", pull: true)
      # Work around the way the helper method invokes the pull_request factory. It takes the user
      # from an internally generated issue
      pull.update!(user: @source_owner)
      issue = create(:issue, user: @source_owner, repository: repo)
      create(:branch_issue_reference, issue: issue, branch_name: "topic", creator: @source_owner)
      pull.close_issue_references.create!(
        issue_id: issue.id,
        source: :manual,
        actor_id: @source_owner
      )

      assert CloseIssueReference.closes(issue).by_user(@source_owner).exists?

      BranchIssueReference.link_pull_request(pull)

      refute BranchIssueReference.by_repo_and_branch(repo, "topic")
    end

    test "does not raise under any circumstances but reports to failbot" do
      @source_owner = create(:user, login: "ari", plan: "large")
      repo, pull = make_repo_and_pull_with_branch(@source_owner, "topic", pull: true)
      # Work around the way the helper method invokes the pull_request factory. It takes the user
      # from an internally generated issue
      pull.update!(user: @source_owner)
      issue = create(:issue, user: @source_owner, repository: repo)
      create(:branch_issue_reference, issue: issue, branch_name: "topic", creator: @source_owner)

      CloseIssueReference.any_instance.expects(:save!).raises(StandardError)
      Failbot.expects(:report!).with(instance_of(StandardError))

      BranchIssueReference.link_pull_request(pull)

      # check that the side effects didn't occur
      refute CloseIssueReference.closes(issue).by_user(@source_owner).exists?
      assert BranchIssueReference.by_repo_and_branch(repo, "topic")
    end

    test "does not create a CloseIssueReference if the issues is a pull request" do
      @source_owner = create(:user, login: "ari", plan: "large")
      repo = create(:repository, owner: @source_owner, from_example: :simple)
      issue = create(:issue, user: @source_owner, repository: repo)

      commit = issue.repository.heads.find("cr-line-endings").sha

      create(:branch_issue_reference, issue: issue, branch_name: "cr-line-endings")

      pull = PullRequest.create_for(repo, {
        base: "master",
        head: "cr-line-endings",
        issue: issue,
        user: @source_owner,
      })

      BranchIssueReference.link_pull_request(pull)

      refute CloseIssueReference.closes(issue).by_user(@source_owner).exists?
      refute BranchIssueReference.by_repo_and_branch(repo, "cr-line-endings")
    end

    test "if the creator is blocked by the user, does not report the issue and deletes the existing branch_issue_reference" do
      issue_creator = create(:user, login: "ari", plan: "large")
      pr_creator = create(:user, login: "ari2", plan: "large")

      repo, pull, _ = make_repo_and_pull_with_branch(pr_creator, "topic", pull: true)
      # Work around the way the helper method invokes the pull_request factory. It takes the user
      # from an internally generated issue
      pull.update!(user: pr_creator)
      issue = create(:issue, user: issue_creator, repository: repo)
      create(:branch_issue_reference, issue: issue, branch_name: "topic", creator: issue_creator)

      issue_creator.block pr_creator

      BranchIssueReference.link_pull_request(pull)

      refute BranchIssueReference.by_repo_and_branch(repo, "topic")
    end
  end

  context ".candidate_branch_name" do
    test "turns the current issue number and title into a potential branch name" do
      issue = create(:issue, number: 123, title: "This is a title")

      assert_equal "123-this-is-a-title", BranchIssueReference.candidate_branch_name(issue: issue)
    end

    test "includes numbers in the title" do
      issue = create(:issue, number: 123, title: "This is a 42 title")

      assert_equal "123-this-is-a-42-title", BranchIssueReference.candidate_branch_name(issue: issue)
    end

    test "strips emojis" do
      issue = create(:issue, number: 123, title: "This is a 🎃 title")

      assert_equal "123-this-is-a-title", BranchIssueReference.candidate_branch_name(issue: issue)
    end

    test "strips all punctuation and brackets" do
      issue = create(:issue, number: 123, title: "[some epic] This (is) & {a} <> title")

      assert_equal "123-some-epic-this-is-a-title", BranchIssueReference.candidate_branch_name(issue: issue)
    end

    test "strips all emoji and punctuation while preserving underscores and non-latin characters" do
      issue = create(:issue, number: 123, title: "[some epic] ↕️ This is a _title_ with emoji 👍 👥 👍🏽 & non-latin characters like é!")

      assert_equal "123-some-epic-this-is-a-_title_-with-emoji-non-latin-characters-like-é", BranchIssueReference.candidate_branch_name(issue: issue)
    end

    test "strips single quotes" do
      issue = create(:issue, number: 111, title: "This is a 'title'")

      assert_equal "111-this-is-a-title", BranchIssueReference.candidate_branch_name(issue: issue)
    end

    test "strips double quotes" do
      issue = create(:issue, number: 456, title: "Create \"Add Iteration\" component and wire it up on the settings page")

      assert_equal "456-create-add-iteration-component-and-wire-it-up-on-the-settings-page", BranchIssueReference.candidate_branch_name(issue: issue)
    end

    test "postfixes a number if the branch name is taken" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      issue = create(:issue, number: 123, user: user, repository: repo, title: "This is a title")

      master_oid = repo.heads["master"].target_oid
      repo.heads.create("123-this-is-a-title", master_oid, user)

      assert_equal "123-this-is-a-title-1", BranchIssueReference.candidate_branch_name(issue: issue)

      repo.heads.create("123-this-is-a-title-1", master_oid, user)

      assert_equal "123-this-is-a-title-2", BranchIssueReference.candidate_branch_name(issue: issue)
    end

    test "considers the target repository if provided" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, number: 123, user: user, repository: repo, title: "This is a title")

      target_repository = create(:repository, owner: user, from_example: :simple)
      master_oid = target_repository.heads["master"].target_oid
      target_repository.heads.create("123-this-is-a-title", master_oid, user)

      assert_equal "123-this-is-a-title", BranchIssueReference.candidate_branch_name(issue: issue)
      assert_equal "123-this-is-a-title-1", BranchIssueReference.candidate_branch_name(issue: issue, repository: target_repository)
    end
  end

  context ".create_with_new_branch!" do
    test "creates a new BranchIssueReference with valid inputs" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      issue = create(:issue, user: user, repository: repo)

      assert_changes -> { BranchIssueReference.count }, 1 do
        new_ref = BranchIssueReference.create_with_new_branch!(
          creator: user,
          issue: issue,
          new_branch_name: "new-branch",
          source_branch_name: "master",
          repository: issue.repository,
          reflog_data: nil
        )

        assert_equal "new-branch", new_ref.branch_name
        assert_equal repo.id, new_ref.issue_repository_id
        assert_equal repo.id, new_ref.branch_repository_id
        assert_equal issue.id, new_ref.issue_id
        assert_equal user.id, new_ref.creator_id
      end
    end

    test "creates a new branch in the repo with valid inputs" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      issue = create(:issue, user: user, repository: repo)

      BranchIssueReference.create_with_new_branch!(
        creator: user,
        issue: issue,
        new_branch_name: "new-branch",
        source_branch_name: "master",
        repository: issue.repository,
        reflog_data: nil
      )

      assert repo.reload.heads.find("new-branch")
    end

    test "does not create a new branch if the BranchIssueReference fails validation" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      issue = create(:issue, user: user, repository: repo)

      assert_raises ActiveRecord::RecordInvalid do
        BranchIssueReference.create_with_new_branch!(
          creator: user,
          issue: issue,
          new_branch_name: "",
          source_branch_name: "master",
          repository: issue.repository,
          reflog_data: nil
        )
      end

      refute repo.reload.heads.find("new-branch")
    end

    test "uses commit_oid over source_branch_name when provided" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      issue = create(:issue, user: user, repository: repo)

      default_oid = issue.repository.heads.find("master").sha
      target_oid = issue.repository.heads.find("cr-line-endings").sha

      BranchIssueReference.create_with_new_branch!(
        creator: user,
        issue: issue,
        new_branch_name: "new-branch",
        source_branch_name: "master",
        repository: issue.repository,
        reflog_data: nil,
        commit_oid: target_oid
      )

      new_branch = repo.reload.heads.find("new-branch")
      assert new_branch
      assert_equal new_branch.sha, target_oid
      refute_equal target_oid, default_oid
    end
  end
end
