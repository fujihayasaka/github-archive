# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationAdvancedSecurityLicenseToggledJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers
  include DogstatsTestHelpers
  extend T::Helpers

  setup do
    @admin = create :user
    @org = create :organization, plan: GitHub::Plan.business_plus
    @member = create(:user)
    @org.add_member(@member)
    @business = create :business, organizations: [@org], owners: [@admin]

    @repo1 = create(:repository, :minimal, owner: @org)
    @repo2 = create(:repository, :minimal, owner: @org)
  end

  test "should raise an error if organization_id is not provided" do
    assert_raises(ArgumentError) do
      OrganizationAdvancedSecurityLicenseToggledJob.perform_later
    end
  end

  test "per-repo hydro messages are published for all repos" do
    OrganizationAdvancedSecurityLicenseToggledJob.perform_now(organization_id: @org.id, original_message: Hydro::Schemas::Github::SecurityCenter::V0::OrganizationAdvancedSecurityLicenseToggled.new)

    assert_hydro_messages(count: @org.repositories.count, schema: "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggledPerRepository")
  end

  context "batch job" do
    test "queues subsequent jobs for batching" do
      repo_count = 9.times do
        repo = create(:repository, owner: @org)
      end

      AbstractOrganizationChangeFanoutJob.stub_const(:BATCH_SIZE, 3) do
        assert_performed_jobs 4, only: OrganizationAdvancedSecurityLicenseToggledJob do
          perform_enqueued_jobs(only: OrganizationAdvancedSecurityLicenseToggledJob) do
            OrganizationAdvancedSecurityLicenseToggledJob.perform_later(organization_id: @org.id)
          end
        end
      end
    end

    test "queries distinct batch of alerts" do
      # 3 repos in first batch, as they are ordered by ID
      repos = [@repo1.id, @repo2.id]
      repos << create(:repository, owner: @org).id

      repo_count = 8.times do
        repo = create(:repository, owner: @org)
      end

      AbstractOrganizationChangeFanoutJob.stub_const(:BATCH_SIZE, 3) do
        batch = OrganizationAdvancedSecurityLicenseToggledJob.new.next_batch(organization_id: @org.id)
        assert_same_elements repos, batch
      end
    end
  end
end
