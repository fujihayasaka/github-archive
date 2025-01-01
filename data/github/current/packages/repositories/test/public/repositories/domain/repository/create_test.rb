# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::CreateTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    @domain = T.let(Repositories::Domain.new(:test, actor: @user), T.nilable(Repositories::Domain))
  end

  sig { returns(Repositories::Domain) }
  def domain
    T.must(@domain)
  end

  test "creates a new repository with expected defaults" do
    attrs = Repositories::CreateRepositoryAttributes.new(
      name: "defaults",
      visibility: Repositories::RepositoryVisibility::Private,
    )

    repo = T.cast(domain.create(attrs), GH::Result::Ok[Repositories::IRepository]).value

    assert_equal @user.login, repo.owner&.login
    assert_equal "defaults", repo.name
    assert_nil repo.description
    assert_equal Repositories::RepositoryVisibility::Private.serialize, repo.visibility
    refute repo.template?
    assert_nil repo.homepage

    # private wikis are a paid feature on Enterprise but public user owned repos are disallowed in multi tenant
    expected_has_wiki = T.cast(repo, Repository).plan_supports?(:wikis) # rubocop:todo GitHub/AvoidCast
    assert_equal expected_has_wiki, repo.has_wiki?

    assert repo.has_issues?
    assert repo.has_projects_enabled?
    assert repo.has_downloads?
    refute repo.discussions_active?
    assert_nil repo.gitignore_template
    assert_nil repo.license
    assert_nil T.cast(repo, Repository).refs["main"] # rubocop:todo GitHub/AvoidCast
    assert repo.merge_commit_allowed?
    assert repo.squash_merge_allowed?
    assert repo.rebase_merge_allowed?
    refute repo.auto_merge_allowed?
    refute repo.delete_branch_on_merge?
    refute repo.enable_update_branch?
    refute repo.squash_pr_title_enabled?
    assert_equal Repositories::SquashCommitMessage::COMMIT_MESSAGES.serialize.upcase,
      repo.squash_merge_commit_message_setting
    assert_equal Repositories::SquashCommitTitle::COMMIT_OR_PR_TITLE.serialize.upcase,
      repo.squash_merge_commit_title_setting
    assert_equal Repositories::MergeCommitTitle::MERGE_MESSAGE.serialize.upcase,
      repo.merge_commit_title_setting
    assert_equal Repositories::MergeCommitMessage::PR_TITLE.serialize.upcase,
      repo.merge_commit_message_setting
  end

  test "creates a new repository with expected values" do
    org = create(:organization)

    # @user must be an admin for delete_branch_on_merge to take effect
    org.add_admin(@user)

    team = T.cast(create(:public_team, organization: org), Team)
    attrs = Repositories::CreateRepositoryAttributes.new(
      owner: org,
      name: "pickles",
      visibility: Repositories::RepositoryVisibility::Private,
      description: "yum (suggested by copilot)",
      template: true,
      homepage: "https://example.com",
      has_wiki: false,
      has_issues: false,
      has_projects: false,
      has_downloads: false,
      has_discussions: true,
      gitignore_template: "Clojure",
      license_template: "MIT",
      auto_init: true,

      allow_auto_merge: true,
      delete_branch_on_merge: true,
      allow_update_branch: true,
      use_squash_pr_title_as_default: true,
      squash_merge_commit_message: Repositories::SquashCommitMessage::PR_BODY,
      squash_merge_commit_title: Repositories::SquashCommitTitle::PR_TITLE,
      merge_commit_title: Repositories::MergeCommitTitle::PR_TITLE,
      merge_commit_message: Repositories::MergeCommitMessage::BLANK,

      team_id: team.id,
    )

    # Avoids `ActiveRecord::RecordInvalid: Validation failed: Updater must exist`
    # See https://github.com/github/repos/issues/11244
    GitHub.context.push(actor_id: @user.id)
    result = T.cast(domain.create(attrs), GH::Result::Ok[Repositories::IRepository]).value

    assert_equal("pickles", result.name)
    assert_equal(org.display_login, result.owner&.display_login)
    assert_equal("yum (suggested by copilot)", result.description)
    assert_equal(Repositories::RepositoryVisibility::Private.serialize, result.visibility)
    assert result.private?
    assert result.template?
    assert_equal "https://example.com", result.homepage
    refute result.has_wiki?
    refute result.has_issues?
    refute result.has_projects_enabled?
    refute result.has_downloads?
    assert result.discussions_active?
    assert_equal "Clojure", result.gitignore_template

    # Setting lincense template only means that the license file is created.
    # The license property is set asynchronously via RepositorySetLicenseJob later.
    repo = T.cast(result, Repository) # rubocop:todo GitHub/AvoidCast
    refute_nil repo.refs["main"]
    assert repo.blob(repo.refs["main"].target.oid, "/LICENSE").data.start_with?("MIT License")

    assert result.auto_merge_allowed?
    assert result.delete_branch_on_merge?
    assert result.enable_update_branch?
    assert result.squash_pr_title_enabled?
    assert_equal Repositories::SquashCommitMessage::PR_BODY.serialize.upcase,
      result.squash_merge_commit_message_setting
    assert_equal Repositories::SquashCommitTitle::PR_TITLE.serialize.upcase,
      result.squash_merge_commit_title_setting
    assert_equal Repositories::MergeCommitTitle::PR_TITLE.serialize.upcase,
      result.merge_commit_title_setting
    assert_equal Repositories::MergeCommitMessage::BLANK.serialize.upcase,
      result.merge_commit_message_setting

    assert_includes team.batched_repositories, result
  end

  test "returns permission failure when there is no actor" do
    attrs = default_attributes(@user)

    result = Repositories::Domain.new(:test).create(attrs)
    assert_kind_of(GH::Result::Error::AccessDenied, result)
  end

  test "returns permission failure when the user is not a member of the organization" do
    org = create(:organization)
    attrs = default_attributes(org)

    result = domain.create(attrs)
    assert_kind_of(GH::Result::Error::AccessDenied, result)
  end

  test "returns permission failure when repo is public but public repos are disallowed globally" do
    attrs = default_attributes(@user)
    attrs.visibility = Repositories::RepositoryVisibility::Public
    GitHub.stubs(:public_repositories_available?).returns(false)

    result = T.cast(domain.create(attrs), GH::Result::Error::AccessDenied[Repositories::IRepository])
    assert_equal("Public repositories not permitted on #{GitHub.flavor}", result.message)
  end

  test "returns permission failure when user tries to create a repo for another user" do
    user2 = create(:user)
    attrs = default_attributes(user2)

    result = domain.create(attrs)
    assert_kind_of(GH::Result::Error::AccessDenied, result)
  end

  test "returns validation failure when invalid data is provided" do
    attrs = default_attributes(@user)
    attrs.name = ""

    result = T.cast(domain.create(attrs), GH::Result::Error::Validation[Repositories::IRepository])
    assert result.model.errors[:name].present?
  end

  test "sets the actor as the owner when owner login is unspecified" do
    attrs = default_attributes(@user)
    attrs.owner = nil

    result = T.cast(domain.create(attrs), GH::Result::Ok[Repositories::IRepository]).value
    assert_equal domain.actor&.id, result.owner&.id
  end

  test "looks up the owner when only the login is provided" do
    org = create(:organization)
    org.add_member(@user)

    attrs = default_attributes(org)
    attrs.owner = org.login

    result = T.cast(domain.create(attrs), GH::Result::Ok[Repositories::IRepository]).value
    assert_equal org.id, result.owner&.id
  end

  test "disallows emu users from creating public repos", skip_enterprise: true do
    user = create(:emu)

    attrs = Repositories::CreateRepositoryAttributes.new(
      name: "defaults",
      visibility: Repositories::RepositoryVisibility::Public,
    )

    domain = Repositories::Domain.new(:test, actor: user)
    result = T.cast(domain.create(attrs), GH::Result::Error::AccessDenied[Repositories::IRepository])

    assert_equal "Public repositories are not permitted for Enterprise Managed Users.", result.message
  end

  private

  def default_attributes(user)
    Repositories::CreateRepositoryAttributes.new(
      owner: user,
      name: "foo",
      visibility: Repositories::RepositoryVisibility::Private,
    )
  end
end
