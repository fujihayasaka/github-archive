# typed: true
# frozen_string_literal: true
require "test_helper"

class Permissions::SearchRepositoryTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @priv_repo = create(:private_repository, :minimal, owner: @owner)
    @member = create(:user)
    @priv_repo.add_member(@member, action: :write)

    @org = create(:organization)
    @org_admin = create(:user)
    @org.add_admin(@org_admin)
    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_repo = create(:repository, :minimal, owner: @org)
    @org_priv_repo = create(:private_repository, :minimal, owner: @org)
  end

  context "ALLOWED" do
    test "user has search permission on private repo if they are member" do
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: @member,
        subject: @priv_repo,
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end

    test "repo owner has search permission" do
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: @owner,
        subject: @priv_repo,
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end

    test "non member has search permission on public org repo" do
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: @member,
        subject: @org_repo,
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end

    test "org member has search permission on public org repo when default permission is :none" do
      @org.update_default_repository_permission(:none, actor: @org.admins.first)

      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: @org_member,
        subject: @org_repo,
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end

    test "org admin has search permission on private repo when default permission is :none" do
      @org.update_default_repository_permission(:none, actor: @org.admins.first)

      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: @org_admin,
        subject: @org_priv_repo,
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end

    test "any user has search permission on public repos" do
      public_repo = create(:repository, :minimal, owner: @owner)
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: create(:user),
        subject: public_repo,
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end

    test "anonymous user has search permission on public repos" do
      public_repo = create(:repository, :minimal, owner: @owner)
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: nil,
        subject: public_repo,
        context: {
          considers_anonymous: true,
        },
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end
  end

  context "DENIED" do
    test "unrelated user does not have search permission for a private repo" do
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: create(:user),
        subject: @priv_repo,
      )
      assert_equal :DENY, decision.result
    end

    test "non member does not have search permission on private org repo" do
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: @member,
        subject: @org_priv_repo,
      )
      assert_equal :DENY, decision.result
    end

    test "org member does not have search permission for private org repo when default permission is :none" do
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @org.admins.first) }

      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: @org_member,
        subject: @org_priv_repo,
      )
      assert_equal :DENY, decision.result
    end

    test "anonymous user does not have search permission for a private repo" do
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: nil,
        subject: @priv_repo,
        context: {
          considers_anonymous: true,
        },
      )
      assert_equal :DENY, decision.result
    end

    test "anonymous user does not have search permission to public repo when considers_anonymous is false " do
      public_repo = create(:repository, :minimal, owner: @owner)
      decision = ::Permissions::Enforcer.authorize(
        action: :search_repository,
        actor: nil,
        subject: public_repo,
        context: {
          considers_anonymous: false,
        },
      )
      assert_equal :DENY, decision.result
    end
  end
end
