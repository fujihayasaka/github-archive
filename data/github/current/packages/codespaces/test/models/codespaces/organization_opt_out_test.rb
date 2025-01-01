# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesOrganizationOptOutTest < GitHub::TestCase
  class FakeAccessControl
    def revoke_billing_permission!(_, _)
      raise Codespaces::OrgPolicy::RoleGranterError.new("Something went wrong")
    end
  end

  fixtures do
    create_org_owner
    create_org
    enable_codespace_for_org
    create_org_member
    add_user_to_org
    enable_codespace_for_user
  end
  context "when removing access from a member raises and exception" do
    test "result returns failure status if a user cannot be removed" do
      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
        access_control: FakeAccessControl.new,
      )
      result = runner.call
      assert_equal result.removed_users, []
    end

    test "marks attempt as failure" do
      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
        access_control: FakeAccessControl.new,
      )

      result = runner.call
      refute result.success?
    end
  end

  context "opting out with valid org with members" do
    test "surfacing organization's members" do
      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
      )
      assert_equal runner.enrolled_members, [@org_member]
    end

    test "removes members when run" do
      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
      )

      runner.call
      assert_equal runner.enrolled_members, []
    end

    test "returns result of removed users" do
      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
      )

      result = runner.call
      assert_equal result.removed_users, [@org_member]
    end

    test "marks attempt as successful" do
      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
      )

      result = runner.call
      assert result.success?
    end

    test "suspends all repos on org's plan", skip_enterprise: true do
      FakeVSOServer.reset!
      private_repo_codespace = create(:codespace, billable_owner: @org_codespaces_enabled, repository: create(:private_repository, owner: @org_codespaces_enabled))
      public_repo_codespace = create(:codespace, billable_owner: @org_codespaces_enabled, repository: create(:repository, owner: @org_codespaces_enabled))
      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
      )

      FakeVSOServer.environments = [
        {
          "id" => private_repo_codespace.guid,
          "updated" => Time.now.iso8601.to_s,
          "plan" => private_repo_codespace.plan.name,
        },
        {
          "id" => public_repo_codespace.guid,
          "updated" => Time.now.iso8601.to_s,
          "plan" => public_repo_codespace.plan.name,
        },
      ]

      runner.call

      assert_enqueued_with(job: CodespacesSuspendEnvironmentJob, args: [codespace: private_repo_codespace])
      assert_enqueued_with(job: CodespacesSuspendEnvironmentJob, args: [codespace: public_repo_codespace])
    end
  end

  context "opting out with outside collaborators" do
    test "surfacing organization's collaborators" do
      repo = create(:private_repository, owner: @org_codespaces_enabled)
      collaborator = create(:user)
      Codespaces::OrgPolicy.grant_billing_permission!(collaborator, @org_codespaces_enabled)
      create(:codespace, repository: repo, owner: collaborator, enable_org_access: false, make_collaborator: true)

      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
      )
      assert_includes runner.enrolled_members, collaborator
    end

    test "removes collaborators when run" do
      repo = create(:private_repository, owner: @org_codespaces_enabled)
      collaborator = create(:user)
      Codespaces::OrgPolicy.grant_billing_permission!(collaborator, @org_codespaces_enabled)
      codespace = create(:codespace, repository: repo, owner: collaborator, enable_org_access: false, make_collaborator: true)

      ::Codespaces::ScheduleEnvironmentSuspension.expects(:call).with(codespace).returns(true)
      runner = Codespaces::OrganizationOptOut.new(
        organization: @org_codespaces_enabled,
        actor: @admin_user,
      )

      runner.call
      assert_equal runner.enrolled_members, []
    end
  end

  private

  def create_org_owner
    @admin_user = create(:user)
  end

  def create_org
    @org_codespaces_enabled = create(:codespaces_organization, plan: GitHub::Plan.business, admin: @admin_user)
  end

  def enable_codespace_for_org
    @org_codespaces_enabled.accept_organization_codespaces_terms(actor: @admin_user)
  end

  def create_org_member
    @org_member = create(:user)
  end

  def add_user_to_org
    @org_codespaces_enabled.add_member(@org_member)
  end

  def enable_codespace_for_user
    Codespaces::OrgPolicy.grant_billing_permission!(@org_member, @org_codespaces_enabled)
  end
end unless GitHub.enterprise?
