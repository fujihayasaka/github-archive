# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionVisibilityCheckerTest < GitHub::TestCase
  def contribution_is_restricted?(associated_subject, user:, viewer: nil)
    subject_map = associated_subject.present? ? { associated_subject.class.to_s => [associated_subject.id] } : nil
    visibility_checker = Contribution::VisibilityChecker.new(user: user, viewer: viewer, subject_map: subject_map)
    visibility_checker.restricted?(associated_subject.class.to_s, associated_subject.id)
  end

  def contribution_is_valid?(associated_subject, user:, viewer: nil, organization_id: nil, skip_restricted: false)
    subject_map = associated_subject.present? ? { associated_subject.class.to_s => [associated_subject.id] } : nil
    visibility_checker = Contribution::VisibilityChecker.new(user: user, viewer: viewer, subject_map: subject_map)
    visibility_checker.valid?(associated_subject.class.to_s, associated_subject.id)
  end

  def valid_repository_ids(repository_ids, skip_restricted: true)
    subject_map = { "Repository" => repository_ids }
    visibility_checker = Contribution::VisibilityChecker.new(user: @user, viewer: @user, subject_map: subject_map)
    visibility_checker.valid_repository_ids(
      repository_ids: repository_ids,
      skip_restricted: skip_restricted,
    )
  end

  setup do
    @user = create(:user)
  end

  context "#valid?" do
    test "returns false if the contribution has an associated subject Repository which is orphaned" do
      repo = create(:repository)
      repo.owner.delete # no callbacks

      refute contribution_is_valid?(repo, user: @user)
    end

    test "returns false if repo is deleted" do
      repo = create(:repository, owner: @user)
      repo.destroy!

      refute Repository.exists?(repo.id)
      refute contribution_is_valid?(repo, user: @user)
    end

    test "returns true for non-repository types" do
      assert contribution_is_valid?(@user, user: @user)
    end
  end

  context "#valid_repository_ids" do
    test "returns empty array if no valid repos" do
      deleted_repo = create(:repository, owner: @user)
      deleted_repo.destroy
      orphaned_repo = create(:repository, owner: @user)
      orphaned_repo.owner.delete # no callbacks
      restricted_repo = create(:private_repository)
      repo_ids = [deleted_repo.id, restricted_repo.id, orphaned_repo.id]

      assert_empty valid_repository_ids(repo_ids)
    end

    test "returns only valid repos" do
      deleted_repo = create(:repository, owner: @user)
      deleted_repo.destroy
      restricted_repo = create(:private_repository)
      valid_repo = create(:repository, owner: @user)
      repo_ids = [deleted_repo.id, restricted_repo.id, valid_repo.id]

      assert_same_elements valid_repository_ids(repo_ids), [valid_repo.id]
    end

    test "returns only valid repos when skip_restricted flag is false" do
      restricted_repo = create(:private_repository, owner: @user)
      valid_repo = create(:repository, owner: @user)
      repo_ids = [restricted_repo.id, valid_repo.id]

      assert_same_elements valid_repository_ids(repo_ids, skip_restricted: false),
        [valid_repo.id, restricted_repo.id]
    end
  end

  context "#restricted?" do
    if GitHub.spamminess_check_enabled?
      test "contributions associated with a repository owned by a spammy org are restricted for anon users" do
        spammy_org = create(:organization, spammy: true)
        spammy_repo = create(:repository, owner: spammy_org)

        assert contribution_is_restricted?(spammy_repo, user: @user)
      end

      test "contributions associated with a repository owned by a spammy user are restricted for anon users" do
        spammy_user = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammy_user)

        assert contribution_is_restricted?(spammy_repo, user: @user)
      end

      test "contributions associated with a repository owned by a spammy user are not restricted for staff users" do
        staff_viewer = create(:staff_admin_user)
        spammy_user = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammy_user)

        refute contribution_is_restricted?(spammy_repo, user: @user, viewer: staff_viewer)
      end

      test "contributions associated with a repository owned by a spammy user are not restricted for that spammy user" do
        spammy_user = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammy_user)

        refute contribution_is_restricted?(spammy_repo, user: @user, viewer: spammy_user)
      end

      test "contributions associated with a repository owned by a spammy user are restricted for contributor" do
        spammy_user = create(:user, spammy: true)
        spammy_repo = create(:repository, owner: spammy_user)

        assert contribution_is_restricted?(spammy_repo, user: @user, viewer: @user)
      end
    end

    test "contributions are restricted by default" do
      visibility_checker = Contribution::VisibilityChecker.new(user: @user, viewer: @user, subject_map: {})
      assert visibility_checker.restricted?(nil, nil)
    end

    test "contributions associated with a public repository are not restricted" do
      repo = create(:repository, owner: @user)

      refute contribution_is_restricted?(repo, user: @user)
      refute contribution_is_restricted?(repo, user: @user, viewer: @user)
      refute contribution_is_restricted?(repo, user: @user, viewer: create(:user))
    end

    test "contributions associated with a disabled repo are restricted for non-staff" do
      staff = create(:staff_admin_user)
      repo = create(:repository, owner: @user)
      repo.access.disable("size", staff)

      assert contribution_is_restricted?(repo, user: @user)
      assert contribution_is_restricted?(repo, user: @user, viewer: @user)
      assert contribution_is_restricted?(repo, user: @user, viewer: create(:user))
      refute contribution_is_restricted?(repo, user: @user, viewer: staff)
    end

    test "contributions associated with a deleted repo are restricted" do
      staff = create(:staff_admin_user)
      repo = create(:repository, :soft_deleted, owner: @user)
      assert repo.deleted?

      assert contribution_is_restricted?(repo, user: @user)
      assert contribution_is_restricted?(repo, user: @user, viewer: @user)
      assert contribution_is_restricted?(repo, user: @user, viewer: create(:user))
      assert contribution_is_restricted?(repo, user: @user, viewer: staff)
    end

    test "contributions associated with a private repository are restricted for viewers without access to the repository" do
      user = create(:user, plan: "medium")
      private_repo = create(:private_repository, owner: user)
      viewer_with_access = create(:user)
      private_repo.add_member(viewer_with_access)

      assert contribution_is_restricted?(private_repo, user: user)
      refute contribution_is_restricted?(private_repo, user: user, viewer: user)
      refute contribution_is_restricted?(private_repo, user: user, viewer: viewer_with_access)
      assert contribution_is_restricted?(private_repo, user: user, viewer: create(:user))
    end

    test "contributions associated with an organization the user is a public member of are not restricted" do
      org = create(:organization)
      org.add_member(@user)
      org.publicize_member(@user)

      refute contribution_is_restricted?(org, user: @user)
      refute contribution_is_restricted?(org, user: @user, viewer: @user)
      refute contribution_is_restricted?(org, user: @user, viewer: create(:user))
    end

    test "contributions associated with an organization are restricted for members" do
      org = create(:organization)
      org.add_member(@user)
      viewer_with_access = create(:user)
      org.add_member(viewer_with_access)

      assert contribution_is_restricted?(org, user: @user)
      refute contribution_is_restricted?(org, user: @user, viewer: @user)
      refute contribution_is_restricted?(org, user: @user, viewer: viewer_with_access)
      assert contribution_is_restricted?(org, user: @user, viewer: create(:user))
    end

    test "contributions associated with an enterprise contribution are restricted for other users" do
      installation = create :enterprise_installation
      contribution = EnterpriseContribution.insert_or_update_contribution(@user, installation, Date.today, 1)

      assert contribution_is_restricted?(contribution, user: create(:user))
      assert contribution_is_restricted?(contribution, user: create(:user), viewer: create(:user))
      refute contribution_is_restricted?(contribution, user: create(:user), viewer: @user)
    end

    test "contributions associated with a user are not restricted" do
      refute contribution_is_restricted?(@user, user: @user)
    end
  end
end
