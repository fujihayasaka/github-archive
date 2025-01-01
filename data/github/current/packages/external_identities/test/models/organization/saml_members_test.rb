# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSamlMembersTest < GitHub::TestCase

  test "returns all non-pending Organization members" do
    org = create(:organization)
    member = create(:user)
    org.add_member(member)

    assert_same_elements [member, org.admin], org.saml_members
  end

  test "does not return collaborators or pending members" do
    org = create(:organization)
    collaborator = create(:user)
    pending_member = create(:user)
    org.invite(pending_member, inviter: org.admin)
    repo = create(:repository, organization: org)
    RepositoryInvitation.invite_to_repo_without_confirmation(collaborator, repo.owner, repo)

    assert_includes org.pending_members, pending_member
    assert_includes repo.members, collaborator
    refute_includes org.saml_members, collaborator
    refute_includes org.saml_members, pending_member
  end
end
