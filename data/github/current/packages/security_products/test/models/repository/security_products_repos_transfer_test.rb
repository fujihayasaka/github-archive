# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProductsReposTransferTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @user = create(:user, plan: "large")
  end

  test "disables ghas for the repo" do
    GitHub.context.push(actor_id: @user.id)

    org_1 = create(:organization, admin: @user)
    org_2 = create(:organization, admin: @user)
    repo = create(:private_repository, owner: org_1)

    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    refute repo.advanced_security_enabled?
    repo.enable_advanced_security!(actor: repo.owner)
    assert repo.advanced_security_enabled?

    repo.transfer_ownership_to(org_2, actor: @user)

    refute repo.advanced_security_enabled?
  end

  test "re-enables ghas for the repo when the new owner is configured to enable ghas on new repositories" do
    GitHub.context.push(actor_id: @user.id)

    org_1 = create(:organization, admin: @user)
    org_2 = create(:organization, admin: @user)
    repo = create(:private_repository, owner: org_1)

    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    org_2.enable_advanced_security_on_new_repos(actor: @user)

    refute repo.advanced_security_enabled?
    repo.enable_advanced_security!(actor: repo.owner)
    assert repo.advanced_security_enabled?

    repo.transfer_ownership_to(org_2, actor: @user)

    assert repo.advanced_security_enabled?
  end

  test "re-enables secret scanning for the repo when the new owner is configured to enable secret scanning on new repositories" do
    GitHub.context.push(actor_id: @user.id)
    org_1 = create(:organization, admin: @user)
    org_2 = create(:organization, admin: @user)
    repo = create(:private_repository, owner: org_1, created_by_user_id: @user.id)

    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    org_2.enable_advanced_security_on_new_repos(actor: @user)
    repo.enable_advanced_security!(actor: repo.owner)

    security_configuration = create(:security_configuration, target: org_2, code_scanning: :not_set, secret_scanning: :enabled)
    default_configuration = create(:security_configuration_default,
      :default_for_new_public_and_private_repos,
      security_configuration: security_configuration
    )

    repo_secret_scanning = SecretScanning::Features::Repo::TokenScanning.new(repo)
    refute repo_secret_scanning.enabled?
    repo_secret_scanning.enable(actor: @user)
    assert repo_secret_scanning.enabled?

    # TODO - I couldn't figure out a way to do it naturally with user permissions, so this stub is a workaround.
    # Simulate enabling the enterprise policy that disallows repo admins from editting secret scanning setting.
    # We want to confirm that it's the repo transfer flow that causes re-enablement,
    # and that re-enablement on repo transfer works even if it fails permission checks on the actor doing the transfer.
    SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_secret_scanning_settings_blocked_by_policy?).returns(true)

    perform_enqueued_jobs only: ApplySecurityConfigurationToRepositoryJob do
      perform_enqueued_hydro_jobs only: [SecurityProductsEnablement::HydroRepositoryTransferredJob] do
        repo.transfer_ownership_to(org_2, actor: @user)
      end
    end

    assert repo_secret_scanning.enabled?
  end
end
