# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitContributionRepositoryValidatorTest < GitHub::TestCase
  fixtures do
    @user = create(:user, plan: "medium")
  end

  def create_validator(repository_ids: Repository.pluck(:id))
    CommitContribution::RepositoryValidator.new(@user, repository_ids: repository_ids)
  end

  test "nil is not a valid repository" do
    validator = create_validator

    refute validator.valid_repository?(nil)
  end

  test "a repository is not valid if it has been deleted" do
    repo = create(:repository)
    repo.add_member(@user)

    validator = create_validator
    assert validator.valid_repository?(repo.id)

    validator = create_validator
    repo.delete
    refute validator.valid_repository?(repo.id)
  end

  test "a repository is not valid if it has been marked for deletion" do
    repo = create(:repository)
    repo.add_member(@user)

    validator = create_validator
    assert validator.valid_repository?(repo.id)

    validator = create_validator
    repo.update(active: nil)
    refute validator.valid_repository?(repo.id)
  end

  test "a repository is not valid when it is not associated with the user" do
    repo = create(:repository)
    validator = create_validator

    refute validator.valid_repository?(repo.id)
  end

  test "a repository is not valid if the owner blocked the user" do
    owner = create(:user)
    repo = create(:repository, owner: owner)
    user_repo = create(:repository, owner: @user)
    @user.star(repo)
    validator = create_validator

    owner.block(@user)
    assert @user.blocked_by?(owner)
    refute validator.valid_repository?(repo.id)
    assert validator.valid_repository?(user_repo.id) # sanity check, user's own repos count
  end if GitHub.user_abuse_mitigation_enabled?

  test "a repository is not valid if the user blocked the owner" do
    owner = create(:user)
    repo = create(:repository, owner: owner)
    @user.star(repo)
    validator = create_validator

    @user.block(owner)
    assert owner.blocked_by?(@user)
    refute validator.valid_repository?(repo.id)
  end if GitHub.user_abuse_mitigation_enabled?

  test "a repository is valid if the user is a collaborator" do
    repo = create(:repository)
    repo.add_member(@user)
    validator = create_validator

    assert validator.valid_repository?(repo.id)
  end

  test "a repository is valid if it's owned by organization the user belongs to" do
    org = create(:organization)
    repo = create(:repository, owner: org)
    org.add_member(@user)
    validator = create_validator

    assert validator.valid_repository?(repo.id)
  end

  test "a repository is valid if it's not accessible by the user but owned by an organization the user belongs to" do
    org = create(:organization, plan: "bronze")
    # Make sure we don't grant read access to repositories by default
    org.update_default_repository_permission(:none, actor: org.admins.first)
    repo = create(:private_repository, owner: org)
    org.add_member(@user)
    validator = create_validator

    refute repo.readable_by?(@user),
      "User should not have any access to the repository"

    assert validator.valid_repository?(repo.id)
  end

  test "a repository is valid if it's owned by an organization the user is a member of via a team" do
    org = create(:organization)
    team = create(:team, organization: org)
    repo = create(:repository, owner: org)
    team.add_member @user
    validator = create_validator

    assert validator.valid_repository?(repo.id)
  end

  test "a repository is valid if it's forked by the user" do
    repo = create(:repository)
    create(:fork_repository, forker: @user, fork_repo: repo)
    validator = create_validator

    assert validator.valid_repository?(repo.id)
  end

  test "a repository is valid if it has an issue created by the user" do
    repo = create(:repository)
    create(:issue, user: @user, repository: repo)
    validator = create_validator

    assert validator.valid_repository?(repo.id)
  end

  test "a repository is valid if it's starred by the user and feature flag is disabled" do
    disable_feature_flag(:disable_starred_repo_validation)
    repo = create(:repository)
    @user.star(repo)
    validator = create_validator

    assert validator.valid_repository?(repo.id)
  end

  test "a repository is invalid if it's starred by the user and feature flag is enabled" do
    enable_feature_flag(:disable_starred_repo_validation)
    repo = create(:repository)
    @user.star(repo)
    validator = create_validator

    refute validator.valid_repository?(repo.id)
  end

  context "whitelisting repositories" do
    test "only considers white labeled starred repositories when feature flag is disabled" do
      disable_feature_flag(:disable_starred_repo_validation)
      repo = create(:repository)
      @user.star(repo)
      validator = create_validator(repository_ids: [])
      refute validator.valid_repository?(repo.id)

      validator = create_validator(repository_ids: [repo.id])
      assert validator.valid_repository?(repo.id)
    end

    test "does not consider white labeled starred repositories when feature flag is enabled" do
      enable_feature_flag(:disable_starred_repo_validation)
      repo = create(:repository)
      @user.star(repo)
      validator = create_validator(repository_ids: [])
      refute validator.valid_repository?(repo.id)

      validator = create_validator(repository_ids: [repo.id])
      refute validator.valid_repository?(repo.id)
    end

    test "only considers white-labeled repositories with an issue" do
      repo = create(:repository)
      create(:issue, user: @user, repository: repo)
      validator = create_validator(repository_ids: [])

      refute validator.valid_repository?(repo.id)

      validator = create_validator(repository_ids: [repo.id])

      assert validator.valid_repository?(repo.id)
    end
  end
end
