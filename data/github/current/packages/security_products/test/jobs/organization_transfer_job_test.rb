# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTransferJobTest < GitHub::TestCase
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

    @repo1 = create(:repository, owner: @org)
    @repo2 = create(:repository, owner: @org)
  end

  test "should raise an error if organization_id is not provided" do
    assert_raises(ArgumentError) do
      OrganizationTransferJob.perform_later
    end
  end


  test "per-repo hydro messages are published for all repos", skip_enterprise: true do
    OrganizationTransferJob.perform_now(organization_id: @org.id, original_message: Hydro::Schemas::Github::EnterpriseAccount::V0::OrganizationTransfer.new)

    assert_hydro_messages(count: @org.repositories.count, schema: "github.enterprise_account.v0.OrganizationTransferPerRepository")
  end

  context "batch job" do
    test "queues subsequent jobs for batching" do
      repo_count = 9.times do
        repo = create(:repository, owner: @org)
      end

      AbstractOrganizationChangeFanoutJob.stub_const(:BATCH_SIZE, 3) do
        assert_performed_jobs 4, only: OrganizationTransferJob do
          perform_enqueued_jobs(only: OrganizationTransferJob) do
            OrganizationTransferJob.perform_later(organization_id: @org.id)
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
        batch = OrganizationTransferJob.new.next_batch(organization_id: @org.id)
        assert_same_elements repos, batch
      end
    end
  end
end
