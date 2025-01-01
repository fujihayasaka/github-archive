# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::Transfers::UninstallUntransferableInstallationsTest < GitHub::TestCase

  fixtures do
    @user = create(:user)

    @integration = create(:integration, owner: @user, default_permissions: { "metadata" => :read })
    @private_user_owned_integration = create(:integration, :private, owner: @user, default_permissions: { "metadata" => :read })

    @business = create(:business)
    @org = create(:organization, business: @business)
    @org.add_member(@user)
    @enterprise_owned_integration = create(:enterprise_owned_integration, owner: @business, default_permissions: { "metadata" => :read })
  end

  context "#cannot_keep_installations_after_transfer?" do
    test "returns false when the integration does not have any installations" do
      transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
        integration: @integration,
        target: @org,
        requester: @user,
        initial_visibility: @integration.visibility,
        initial_owner: @user
      )
      refute transfer_management.cannot_keep_installations_after_transfer?
    end

    test "returns false when an integration with installations is transferred to a user" do
      org_owned_integration = create(:integration, owner: @org, default_permissions: { "metadata" => :read })
      make_integration_installation(integration: org_owned_integration, target: @org)

      transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
        integration: org_owned_integration,
        target: @user,
        requester: @user,
        initial_visibility: org_owned_integration.visibility,
        initial_owner: @org
      )
      refute transfer_management.cannot_keep_installations_after_transfer?
    end

    test "returns false when an integration with installations is transferred to an organization" do
      make_integration_installation(integration: @integration, target: @user)

      transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
        integration: @integration,
        target: @org,
        requester: @user,
        initial_visibility: @integration.visibility,
        initial_owner: @user
      )
      refute transfer_management.cannot_keep_installations_after_transfer?
    end

    test "returns false when an integration with installations is transferred from an enterprise to an enterprise" do
      make_integration_installation(integration: @enterprise_owned_integration, target: @org)
      another_business = create(:business)

      transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
        integration: @enterprise_owned_integration,
        target: another_business,
        requester: @user,
        initial_visibility: @enterprise_owned_integration.visibility,
        initial_owner: @business
      )
      refute transfer_management.cannot_keep_installations_after_transfer?
    end unless GitHub.single_business_environment?

    context "private apps" do
      test "returns true when transferring from a user to a user" do
        private_user_integration = create(:integration, :private, owner: @user, default_permissions: { "metadata" => :read })
        make_integration_installation(integration: private_user_integration, target: @user)

        another_user = create(:user)

        transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
          integration: private_user_integration,
          target: another_user,
          requester: another_user,
          initial_visibility: "private_visibility",
          initial_owner: @user
        )
        assert transfer_management.cannot_keep_installations_after_transfer?
      end

      test "returns true when transferring from a user to an organization" do
        private_user_integration = create(:integration, :private, owner: @user, default_permissions: { "metadata" => :read })
        make_integration_installation(integration: private_user_integration, target: @user)

        transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
          integration: private_user_integration,
          target: @org,
          requester: @user,
          initial_visibility: "private_visibility",
          initial_owner: @user
        )
        assert transfer_management.cannot_keep_installations_after_transfer?
      end

      test "returns true when transferring from a user to an enterprise" do
        private_user_integration = create(:integration, :private, owner: @user, default_permissions: { "metadata" => :read })
        make_integration_installation(integration: private_user_integration, target: @user)

        transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
          integration: private_user_integration,
          target: @business,
          requester: @user,
          initial_visibility: "private_visibility",
          initial_owner: @user
        )
        assert transfer_management.cannot_keep_installations_after_transfer?
      end

      test "returns true when transferring from an organization to a user" do
        private_org_integration = create(:integration, :private, owner: @org, default_permissions: { "metadata" => :read })
        make_integration_installation(integration: private_org_integration, target: @org)

        transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
          integration: private_org_integration,
          target: @user,
          requester: @user,
          initial_visibility: "private_visibility",
          initial_owner: @org
        )
        assert transfer_management.cannot_keep_installations_after_transfer?
      end

      test "returns true when transferring from an organization to an organization" do
        private_org_integration = create(:integration, :private, owner: @org, default_permissions: { "metadata" => :read })
        make_integration_installation(integration: private_org_integration, target: @org)

        another_org = create(:organization)

        transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
          integration: private_org_integration,
          target: another_org,
          requester: @user,
          initial_visibility: "private_visibility",
          initial_owner: @org
        )
        assert transfer_management.cannot_keep_installations_after_transfer?
      end

      test "returns false when transferring from an organization to an enterprise" do
        private_org_integration = create(:integration, :private, owner: @org, default_permissions: { "metadata" => :read })
        make_integration_installation(integration: private_org_integration, target: @org)

        transfer_management = Integration::Transfers::UninstallUntransferableInstallations.new(
          integration: private_org_integration,
          target: @business,
          requester: @user,
          initial_visibility: "private_visibility",
          initial_owner: @org
        )
        refute transfer_management.cannot_keep_installations_after_transfer?
      end
    end
  end

  context "#perform" do
    test "uninstalls all installations" do
      make_integration_installation(integration: @private_user_owned_integration, target: @user)

      assert_changes -> { @private_user_owned_integration.installations.count }, from: 1, to: 0 do
        perform_enqueued_jobs only: [UninstallIntegrationInstallationJob] do
          Integration::Transfers::UninstallUntransferableInstallations.new(
            integration: @private_user_owned_integration,
            target: @business,
            requester: @user,
            initial_visibility: "private_visibility",
            initial_owner: @user
          ).perform
        end
      end
    end

    test "skips uninstallation if it is not required" do
      make_integration_installation(integration: @integration, target: @user)

      assert_no_difference -> { @integration.installations.count } do
        perform_enqueued_jobs only: [UninstallIntegrationInstallationJob] do
          Integration::Transfers::UninstallUntransferableInstallations.new(
            integration: @integration,
            target: @org,
            requester: @user,
            initial_visibility: "public_visibility",
            initial_owner: @user
          ).perform
        end
      end
    end
  end

end
