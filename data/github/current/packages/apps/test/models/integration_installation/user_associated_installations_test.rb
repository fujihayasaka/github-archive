# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallation::UserAssociatedInstallationsTest < GitHub::TestCase
  fixtures do
    @admin = create(:paid_user)
    @member = create(:user)
    @collaborator = create(:user)
    @integration = create(:integration, default_permissions: { "metadata" => :read })
    @another_integration = create(:integration, default_permissions: { "metadata" => :read })
    @org   = create(:organization, admin: @admin)
    @org.add_member(@member)
    @repo  = create(:private_repository, :minimal, owner: @org)
    @repo.add_member(@collaborator)
    @public_repo = create(:repository, :minimal, owner: @org)
    @user_repo = create(:private_repository, :minimal, owner: @admin)
    @installation = make_integration_installation(integration: @integration, repository: @repo)
    @user_installation = make_integration_installation(integration: @integration, repository: @user_repo)
    @org_installation = make_integration_installation(target: @org, repository: create(:private_repository, :minimal, owner: @org))
  end

  def associated_installations(user:, repository_ids: nil, excluded_organization_ids: [])
    ::IntegrationInstallation::UserAssociatedInstallations.associated_installations(
      user: user, repository_ids: repository_ids, excluded_organization_ids: excluded_organization_ids
    )
  end

  test "includes user installations" do
    installations = associated_installations(user: @admin)
    assert_includes installations, @user_installation
  end

  test "includes org installations where user is an org admin" do
    installations = associated_installations(user: @admin)
    assert_includes installations, @installation
  end

  test "includes org installations where user is a member" do
    installations = associated_installations(user: @member)
    assert_includes installations, @installation
  end

  test "includes org installations on a repository where user is an outside collaborator" do
    installations = associated_installations(user: @collaborator)
    assert_includes installations, @installation
  end

  test "should includes user installations on a repository where user is an outside collaborator" do
    user = create(:user)
    repo = create(:repository, owner: user)
    user_collaborator = create(:user)
    repo.add_member(user_collaborator)
    assert user_collaborator.associated_repository_ids.include? repo.id

    installation = make_integration_installation(repository: repo, permissions: { "metadata" => :read })

    installations = associated_installations(user: user_collaborator)
    assert_includes installations, installation
  end

  test "includes user installations without metadata permissions" do
    integration = create(:integration, default_permissions: { "issues" => :read })

    installation = integration.install_on(
      @admin,
      repositories: [@user_repo],
      installer: @admin,
      entry_point: :test_case
    ).installation
    refute_includes installation.permissions, :metadata

    installations = associated_installations(user: @admin)
    assert_includes installations, installation
  end

  test "excludes org installations where user is an outside collaborator" do
    installations = associated_installations(user: @collaborator)
    refute_includes installations, @org_installation
  end

  test "includes an installation on all repositories" do
    user = create(:user)
    org = create(:organization)
    repo = create(:repository, owner: org)
    repo.add_member(user)
    assert user.associated_repository_ids.include? repo.id

    installation = make_integration_installation(target: org, integration: @integration)

    installations = associated_installations(user: user)
    assert_includes installations, installation
  end

  # See https://github.com/github/ecosystem-apps/issues/664
  # installation on forked private repositories considered accessible to user
  test "excludes installations on accessible organization private repositories that have been forked" do
    org = create(:organization)
    org.update_default_repository_permission(:none, actor: org.admins.first)
    repo = create(:private_repository, owner: org)
    org.allow_private_repository_forking(actor: org.admins.first)

    user = create(:user)
    forker_user = create(:user)

    org.add_member user
    org.add_member forker_user
    repo.add_member user
    repo.add_member forker_user

    forked_repo, reason, errors = repo.fork(forker: forker_user)
    installation = make_integration_installation(repository: forked_repo, permissions: { "metadata" => :read })

    installations = associated_installations(user: user)
    refute_includes installations, installation
  end

  test "does not filter non-owned/adminned repository IDs when not specified" do
    other_repo1, other_repo2 = create_list(:repository, 2, owner: @collaborator, public: false)
    other_repo1.add_member @admin
    other_repo2.add_member @admin
    collab_installation1 = make_integration_installation(repository: other_repo1, permissions: { "metadata" => :read })
    collab_installation2 = make_integration_installation(repository: other_repo2, permissions: { "metadata" => :read })

    installations = associated_installations(user: @admin)
    assert_includes installations, @org_installation
    assert_includes installations, @user_installation
    assert_includes installations, collab_installation1
    assert_includes installations, collab_installation2
  end

  test "filters non-owned/adminned repository IDs when specified" do
    other_repo1, other_repo2 = create_list(:repository, 2, owner: @collaborator, public: false)
    other_repo1.add_member @admin
    other_repo2.add_member @admin
    collab_installation1 = make_integration_installation(repository: other_repo1, permissions: { "metadata" => :read })
    collab_installation2 = make_integration_installation(repository: other_repo2, permissions: { "metadata" => :read })

    installations = associated_installations(user: @admin, repository_ids: [other_repo1.id])
    assert_includes installations, @org_installation
    assert_includes installations, @user_installation
    assert_includes installations, collab_installation1
    refute_includes installations, collab_installation2
  end
end
