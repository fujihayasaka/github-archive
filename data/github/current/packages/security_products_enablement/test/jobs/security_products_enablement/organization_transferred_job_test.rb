# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/turboghas_helpers"

module SecurityProductsEnablement
  # Note on GHES, there is only one business so organization transfers aren't thing
  class OrganizationTransferredJobTest < GitHub::TestCase
    include JobTestHelper
    include TurboghasHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers
    include DogstatsTestHelpers
    extend T::Helpers

    setup do
      @admin = create(:verified_user)
      @org1 = create(:organization, admin: @user, business: @business)
      @org2 = create(:organization, admin: @user, business: @other_business)
      @business = create :business, organizations: [@org1], owners: [@admin], name: "business"
      @other_business = create :business, organizations: [@org2], owners: [@admin], name: "other business"

      @enterprise_security_configuration = create(:security_configuration, target: @business, name: "business elc")
      @other_enterprise_security_configuration = create(:security_configuration, target: @other_business, name: "other business elc")

      # Stubs necessary for GHAS checks:
      Business.any_instance.stubs(
        advanced_security_purchased?: true,
        advanced_security_seats_for_entity: 1_234
      )

      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      AdvancedSecurityLicense.any_instance.stubs(:unlimited_seats?).returns(true)
      GitHub.stubs(:code_scanning_enabled?).returns(true)

      # stub autocodeql methods
      GitHub.stubs(:actions_enabled?).returns(true)
      CodeScanning::Status.stubs(:mac_os_runner?).returns(true)
      CodeScanning::Status.stubs(:validate_prerequisites)
      CodeScanning::AutoCodeql.any_instance.stubs(:enabled?).returns(false)
      CodeScanning::AutoCodeql.any_instance.stubs(:on_enable).returns(SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, nil))
    end

    test "should raise an error if organization_id is not provided" do
      assert_raises(ArgumentError) do
        OrganizationTransferredJob.perform_later
      end
    end

    test "Applies the destination enterprise's default config to all repos in the transferred org" do
      # Assume the transfer is complete at this point, so setting test org's business to the new business
      # It is safe to make this assumption because the job is enqueued when the hydro message is received
      # which is after the transfer is complete

      repo1 = create(:private_repository, owner: @org2)
      repo2 = create(:private_repository, owner: @org2)
      repo3 = create(:private_repository, owner: @org2)

      # simulate the repos being attached to an old enterprise config
      [repo1, repo2, repo3].each do |repo|
        create(:repository_security_configuration,
          repository: repo,
          security_configuration: @enterprise_security_configuration,
          state: :attached
        )
      end

      create(
        :security_configuration_default,
        :default_for_new_public_and_private_repos,
        security_configuration: @other_enterprise_security_configuration
      )

      assert_equal repo1.security_configuration.id, @enterprise_security_configuration.id
      assert_equal repo2.security_configuration.id, @enterprise_security_configuration.id

      assert_performed_jobs 3, only: ApplySecurityConfigurationToRepositoryJob do
        OrganizationTransferredJob.perform_now(
          organization_id: @org2.id,
          actor: @admin,
          destination_enterprise: @other_business
        )
      end

      [repo1, repo2, repo3].each do |repo|
        repo.reload
        assert_equal repo.security_configuration.id, @other_enterprise_security_configuration.id
      end
    end

    test "deletes the old enterprise level repository security configuration if there is no default config in the new enterprise" do
      repo1 = create(:private_repository, owner: @org2)
      create(:repository_security_configuration,
        repository: repo1,
        security_configuration: @enterprise_security_configuration,
        state: :attached
      )

      assert_equal repo1.security_configuration.id, @enterprise_security_configuration.id

      assert_performed_jobs 0, only: ApplySecurityConfigurationToRepositoryJob do
        OrganizationTransferredJob.perform_now(
          organization_id: @org2.id,
          actor: @admin,
          destination_enterprise: @other_business
        )
      end

      repo1.reload
      assert_nil repo1.security_configuration
    end
  end
end unless GitHub.enterprise?
