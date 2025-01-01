# typed: true
# frozen_string_literal: true

require "test_helper"

# Note on GHES, there is only one business so organization transfers aren't thing
class HydroOrganizationTransferredJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    # referencing the job class forces it to load, so it can be looked up by queue name
    @queue = SecurityProductsEnablement::HydroOrganizationTransferredJob.queue_name
    @schema = "github.enterprise_account.v0.OrganizationTransfer"
  end

  setup do
    @admin = create(:verified_user)
    @org1 = create(:organization, admin: @user, business: @business)
    @business = create :business, organizations: [@org1], owners: [@admin], name: "business"
    @other_business = create :business, owners: [@admin], name: "other business"

    @enterprise_security_configuration = create(:security_configuration, target: @business, name: "business elc")
    @other_enterprise_security_configuration = create(:security_configuration, target: @other_business, name: "other business elc")

    # Stubs necessary for GHAS checks:
    Business.any_instance.stubs(
      advanced_security_purchased?: true,
      advanced_security_seats_for_entity: 1_234
    )

    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    AdvancedSecurityLicense.any_instance.stubs(:unlimited_seats?).returns(true)
  end

  test "the job enqueues a ApplySecurityConfigurationToRepositoryJob" do
    GitHub.flipper[:enterprise_security_configurations].enable

    create(
      :security_configuration_default,
      :default_for_new_public_and_private_repos,
      security_configuration: @enterprise_security_configuration
    )
    create(
      :security_configuration_default,
      :default_for_new_public_and_private_repos,
      security_configuration: @other_enterprise_security_configuration
    )

    message = {
      organization: Hydro::EntitySerializer.organization(@org1),
      source_enterprise: Hydro::EntitySerializer.business(@business),
      destination_enterprise: Hydro::EntitySerializer.business(@other_business),
      actor: Hydro::EntitySerializer.user(@admin),
      completed_at: Time.now,
      site_admin_transfer: false,
    }

    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end

    # Assert that the job was enqueued
    expected_args = {
      organization_id: @org1.id,
      actor: @admin,
      destination_enterprise: @other_business,
    }

    assert_enqueued_with job: SecurityProductsEnablement::OrganizationTransferredJob, args: [expected_args]
  end
end unless GitHub.enterprise?
