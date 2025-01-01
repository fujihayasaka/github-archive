# typed: true
# frozen_string_literal: true

require "test_helper"

class PermissionTest < GitHub::TestCase
  test "defines valid FGP actors" do
    assert_same_elements %w[
      IntegrationInstallation
      OauthAuthorization
      OrganizationProgrammaticAccessGrant
      OrganizationProgrammaticAccessGrantRequest
      ScopedIntegrationInstallation
      SiteScopedIntegrationInstallation
      User
      UserProgrammaticAccessGrant
      UserProgrammaticAccessGrantRequest
    ], Permission::FGP_ACTORS
  end

  test "subject returns ability collection for business resource" do
    business = create(:business)
    permission = Permission.create(
      subject_id: business.id,
      subject_type: Business::Resources.all_prefixed_subject_types.first,
      actor: create(:integration_installation)
    )

    assert_equal business, permission.subject.parent
    assert_equal Business::Resources.all_prefixed_subject_types.first.split("/").last, permission.subject.name
  end

  test "subject returns ability collection based off user for user resources" do
    user = create(:user)
    permission = Permission.create(
      subject_id: user.owner.id,
      subject_type: User::Resources.all_prefixed_subject_types.first,
      actor: create(:integration_installation)
    )

    assert_equal user.owner, permission.subject.parent
    assert_equal User::Resources.all_prefixed_subject_types.first.split("/").last, permission.subject.name
  end

  test "subject returns ability collection based off owner for repository resource installed on all" do
    repository = create(:repository)
    permission = Permission.create(
      subject_id: repository.owner.id,
      subject_type: Repository::Resources.all_prefixed_subject_types.first,
      actor: create(:integration_installation)
    )

    assert_equal repository.owner, permission.subject.parent
    assert_equal Repository::Resources.all_prefixed_subject_types.first.split("/").last, permission.subject.name
  end

  test "subject returns ability collection based off owner for repository resource installed on individual repos" do
    repository = create(:repository)
    permission = Permission.create(
      subject_id: repository.id,
      subject_type: Repository::Resources.individual_type_prefixed_subject_types.first,
      actor: create(:integration_installation)
    )

    assert_equal repository, permission.subject.parent
    assert_equal Repository::Resources.individual_type_prefixed_subject_types.first.split("/").last, permission.subject.name
  end
end
