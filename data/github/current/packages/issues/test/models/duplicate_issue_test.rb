# typed: true
# frozen_string_literal: true

require "test_helper"

class DuplicateIssueTest < GitHub::TestCase
  fixtures do
    @duplicate_issue = create(:duplicate_issue, duplicate: true)
    @org = create(:business_plus_organization)
    @org_repo = create(:repository, owner: @org)
    @org_team = create(:team, organization: @org, privacy: :closed)
    @org_issue = create(:issue, repository: @org_repo)
    @org_repo_dupe_issue = create(:duplicate_issue, issue: @org_issue)
  end

  context "validations" do
    test "requires an issue" do
      dupe_issue = build(:duplicate_issue, issue: nil)

      refute_predicate dupe_issue, :valid?
    end

    test "requires a canonical issue" do
      dupe_issue = build(:duplicate_issue, canonical_issue: nil)

      refute_predicate dupe_issue, :valid?
    end

    test "issue can not be changed after creation" do
      issue_id = @duplicate_issue.issue.id
      other_issue = create(:issue)
      @duplicate_issue.issue = other_issue
      @duplicate_issue.save!

      @duplicate_issue = DuplicateIssue.find(@duplicate_issue.id)

      assert_equal issue_id, @duplicate_issue.issue_id
    end

    test "canonical_issue can not be changed after creation" do
      issue_id = @duplicate_issue.canonical_issue.id
      other_issue = create(:issue)
      @duplicate_issue.canonical_issue = other_issue
      @duplicate_issue.save!

      assert_equal issue_id, @duplicate_issue.reload.canonical_issue_id
    end

    test "repository can not be changed after creation" do
      repo_id = @duplicate_issue.repository_id
      other_repo = create(:repository)
      @duplicate_issue.repository = other_repo
      @duplicate_issue.save!

      assert_equal repo_id, @duplicate_issue.reload.repository_id
    end

    test "repository_id can not be changed after creation" do
      repository_id = @duplicate_issue.repository.id
      other_repo = create(:repository)

      @duplicate_issue.repository_id = other_repo.id
      @duplicate_issue.save!

      assert_equal repository_id, @duplicate_issue.repository_id
    end

    test "requires issue and canonical issue differ" do
      issue = create(:issue)
      dupe_issue = build(:duplicate_issue, issue: issue, canonical_issue: issue)

      refute_predicate dupe_issue, :valid?
    end

    test "requires an actor" do
      dupe_issue = build(:duplicate_issue, actor: nil)

      refute_predicate dupe_issue, :valid?
    end

    test "disallows same dupe + canonical pair more than once" do
      existing = create(:duplicate_issue)
      dupe_issue = build(:duplicate_issue, issue_id: existing.issue_id,
                                               canonical_issue_id: existing.canonical_issue_id)

      refute_predicate dupe_issue, :valid?
    end

    test "requires issue to have repository_id" do
      issue = create(:issue)
      canonical = create(:issue)
      issue.repository_id = nil
      assert_raises(ActiveRecord::RecordInvalid) do
        dupe_issue = create(:duplicate_issue, issue: issue, canonical_issue: canonical)
      end
    end

    test "sets repository_id for newly created duplicate issue" do
      issue = create(:issue)
      canonical = create(:issue)
      dupe_issue = create(:duplicate_issue, issue: issue, canonical_issue: canonical)

      refute_nil dupe_issue.repository_id
      assert_equal issue.repository_id, dupe_issue.repository_id
    end
  end

  context ".find_or_build_for" do
    test "updates duplicate status and actor for existing record" do
      existing = create(:duplicate_issue, duplicate: true)
      new_actor = create(:user)

      assert_no_difference "DuplicateIssue.count" do
        actual = DuplicateIssue.find_or_build_for(issue: existing.issue, user: new_actor,
                                                  canonical_issue: existing.canonical_issue,
                                                  is_duplicate: false)

        assert_predicate actual, :changed?
        assert_equal new_actor, actual.actor
        assert_equal existing.id, actual.id
        refute_predicate actual, :duplicate?
      end
    end

    test "returns a new record for a new issue pair" do
      actor = create(:user)
      issue = create(:issue)
      canonical_issue = create(:issue)

      assert_no_difference "DuplicateIssue.count" do
        dupe = DuplicateIssue.find_or_build_for(issue: issue, canonical_issue: canonical_issue,
                                                user: actor)

        assert_predicate dupe, :new_record?
        assert_equal actor, dupe.actor
        assert_equal issue, dupe.issue
        assert_equal canonical_issue, dupe.canonical_issue
      end
    end
  end

  context "#async_editable_by?" do
    test "is false for nil user" do
      assert_equal false, @duplicate_issue.async_editable_by?(nil).sync
    end

    test "is false without write access" do
      assert_equal false, @duplicate_issue.async_editable_by?(create(:user)).sync
    end

    test "is true with write access" do
      assert_equal true, @duplicate_issue.async_editable_by?(@duplicate_issue.repository.owner).sync
    end

    test "is true without write access but actor was viewer" do
      assert_equal true, @duplicate_issue.async_editable_by?(@duplicate_issue.actor).sync
    end
  end

  context "#with_canonical_and_duplicates" do
    test "lists expected records" do
      dupe2 = create(:duplicate_issue, duplicate: true)
      dupe3 = create(:duplicate_issue, duplicate: true, issue: dupe2.issue)
      results = DuplicateIssue.with_canonical_and_duplicates([
        [@duplicate_issue.canonical_issue_id, @duplicate_issue.issue_id],
        [dupe2.canonical_issue_id, dupe2.issue_id]])

      refute_includes results, dupe3
      assert_includes results, dupe2
      assert_includes results, @duplicate_issue
    end
  end

  context "#can_unmark_as_duplicate?" do
    test "returns false when no user is provided" do
      Platform::Loaders::Permissions::BatchAuthorize.expects(:load).never
      refute @duplicate_issue.can_unmark_as_duplicate?(nil)
    end

    test "returns false for any old user" do
      rando = create(:user)
      refute @duplicate_issue.can_unmark_as_duplicate?(rando)
    end

    test "returns true for repository owner" do
      owner = @duplicate_issue.repository.owner
      assert @duplicate_issue.can_unmark_as_duplicate?(owner)
    end

    test "returns false contributor with read permissions" do
      collaborator_with_read = create :user
      @duplicate_issue.repository.add_member(collaborator_with_read, action: :read)
      refute @duplicate_issue.can_unmark_as_duplicate?(collaborator_with_read)
    end

    test "returns true contributor with write permissions" do
      collaborator_with_write = create :user
      @duplicate_issue.repository.add_member(collaborator_with_write, action: :write)
      assert @duplicate_issue.can_unmark_as_duplicate?(collaborator_with_write)
    end

    test "returns false for user with read access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :read)
      refute @org_repo_dupe_issue.can_unmark_as_duplicate?(org_member)
    end

    test "returns false for a member of team with read on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :pull
      refute @org_repo_dupe_issue.can_unmark_as_duplicate?(team_member)
    end

    test "returns true for user with write access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :write)
      assert @org_repo_dupe_issue.can_unmark_as_duplicate?(org_member)
    end

    test "returns true if a staff user has a repository unlock" do
      owner = @duplicate_issue.repository.owner
      unlocker = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
      grant = create :staff_access_grant, accessible: @org_repo_dupe_issue.repository, granted_by: owner
      assert unlocker.unlock_repository(@org_repo_dupe_issue.repository)
      assert @org_repo_dupe_issue.can_unmark_as_duplicate?(unlocker)
    end

    test "returns true for user with triage access on org owned repo" do
      org_member = create :user
      @org_repo.add_member(org_member, action: :triage)
      assert @org_repo_dupe_issue.can_unmark_as_duplicate?(org_member)
    end

    test "returns true for a member of team with triage on org owned repo" do
      team_member = create :user
      @org_team.add_member(team_member)
      @org_team.add_repository @org_repo, :triage
      assert @org_repo_dupe_issue.can_unmark_as_duplicate?(team_member)
    end
  end
end
