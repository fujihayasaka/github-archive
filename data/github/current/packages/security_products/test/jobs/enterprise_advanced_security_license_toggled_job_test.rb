# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseAdvancedSecurityLicenseToggledJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers
  include DogstatsTestHelpers
  extend T::Helpers

  fixtures do
    @admin = create :user
    @org = create :organization, plan: GitHub::Plan.business_plus
    @org2 = create :organization, plan: GitHub::Plan.business_plus
    @member = create(:user)
    @org.add_member(@member)
    @org2.add_member(@member)
    @business = create :business, organizations: [@org, @org2], owners: [@admin]
  end

  test "should raise an error if business_id is not provided" do
    assert_raises(ArgumentError) do
      EnterpriseAdvancedSecurityLicenseToggledJob.perform_later
    end
  end


  test "per-repo hydro messages are published for all orgs" do
    EnterpriseAdvancedSecurityLicenseToggledJob.perform_now(business_id: @business.id, original_message: Hydro::Schemas::Github::SecurityCenter::V0::EnterpriseAdvancedSecurityLicenseToggled.new)

    assert_hydro_messages(count: @business.organizations.count, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled")
  end

  context "batch job" do
    test "queues subsequent jobs for batching" do
      org_count = 9.times do
        org = create :organization, plan: GitHub::Plan.business_plus
        @business.add_organization(org)
      end

      AbstractEnterpriseChangeFanoutJob.stub_const(:BATCH_SIZE, 3) do
        assert_performed_jobs 4, only: EnterpriseAdvancedSecurityLicenseToggledJob do
          perform_enqueued_jobs(only: EnterpriseAdvancedSecurityLicenseToggledJob) do
            EnterpriseAdvancedSecurityLicenseToggledJob.perform_later(business_id: @business.id)
          end
        end
      end
    end

    test "queries distinct batch of alerts" do
      # 3 orgs in first batch, as they are ordered by ID
      orgs = [@org.id, @org2.id]
      org3 = create :organization, plan: GitHub::Plan.business_plus
      orgs << org3.id
      @business.add_organization(org3)

      org_count = 8.times do
        org = create :organization, plan: GitHub::Plan.business_plus
        @business.add_organization(org)
      end

      AbstractEnterpriseChangeFanoutJob.stub_const(:BATCH_SIZE, 3) do
        batch = EnterpriseAdvancedSecurityLicenseToggledJob.new.next_batch(business_id: @business.id)
        assert_same_elements orgs, batch
      end
    end

    context "soft-deleted organizations", skip_enterprise: true do
      test "does not queue jobs for soft-deleted organizations" do
        assert_equal 2, @business.organizations.count

        perform_enqueued_jobs only: [SoftDeleteBusinessJob] do
          @org2.soft_delete!(@admin)
        end

        assert_equal 1, @business.organizations.count

        AbstractEnterpriseChangeFanoutJob.stub_const(:BATCH_SIZE, 2) do
          assert_performed_jobs 1, only: EnterpriseAdvancedSecurityLicenseToggledJob do
            perform_enqueued_jobs(only: EnterpriseAdvancedSecurityLicenseToggledJob) do
              EnterpriseAdvancedSecurityLicenseToggledJob.perform_later(business_id: @business.id)
            end
          end
        end
      end

    end
  end
end
