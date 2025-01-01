# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationUpgradeJobTest < GitHub::TestCase
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

    original_event_time = Time.now
    original_event_timestamp = Google::Protobuf::Timestamp.new(seconds: original_event_time.to_i, nanos: original_event_time.nsec)
    @envelope = Hydro::Schemas::Hydro::V1::Envelope.new(timestamp: original_event_timestamp).to_h
  end

  test "should raise an error if organization_id is not provided" do
    assert_raises(ArgumentError) do
      OrganizationUpgradeJob.perform_later
    end
  end


  test "per-repo hydro messages are published for all repos", skip_enterprise: true do
    OrganizationUpgradeJob.perform_now(organization_id: @org.id, original_message: Hydro::Schemas::Github::EnterpriseAccount::V0::OrganizationUpgrade.new, original_message_envelope: @envelope)

    assert_hydro_messages(count: @org.repositories.count, schema: "github.enterprise_account.v0.OrganizationUpgradePerRepository")
  end

  context "batch job" do
    test "queues subsequent jobs for batching" do
      repo_count = 9.times do
        repo = create(:repository, owner: @org)
      end

      AbstractOrganizationChangeFanoutJob.stub_const(:BATCH_SIZE, 3) do
        assert_performed_jobs 4, only: OrganizationUpgradeJob do
          perform_enqueued_jobs(only: OrganizationUpgradeJob) do
            OrganizationUpgradeJob.perform_later(organization_id: @org.id, original_message_envelope: @envelope)
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
        batch = OrganizationUpgradeJob.new.next_batch(organization_id: @org.id)
        assert_same_elements repos, batch
      end
    end
  end
end
