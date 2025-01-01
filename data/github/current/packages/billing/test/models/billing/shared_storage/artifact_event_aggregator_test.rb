# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::SharedStorage
  class ArtifactEventAggregatorTest < GitHub::TestCase
    include ::Billing::ApiTestHelpers

    setup do
      ActionMailer::Base.deliveries.clear
      GitHub.flipper[:actions_storage_migration_skip].disable
      GitHub.flipper[:skip_shared_storage_aggregation].disable
    end

    test "it aggregates current usage records for the current owner based on repos found in events" do
      billable_owner = create(:business)
      owner = create(:organization, business: billable_owner)
      repo1, repo2, repo3 = create_list(:repository, 3, owner: owner)
      current_usage1 = create(:shared_storage_current_usage, owner: owner, repository: repo1)
      current_usage3 = create(:shared_storage_current_usage, owner: owner, repository: repo3)
      current_usage4 = create(:shared_storage_current_usage, owner: owner, repository_id: 0)

      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo1)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo2)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo3)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: nil, owner: owner)

      cutoff = Time.current

      CurrentUsage.expects(:find_by)
        .with({ owner: owner, repository_id: repo1.id }).returns(current_usage1)
      CurrentUsage.expects(:find_by)
        .with({ owner: owner, repository_id: repo2.id }).returns(nil)
      CurrentUsage.expects(:find_by)
        .with({ owner: owner, repository_id: repo3.id }).returns(current_usage3)
      CurrentUsage.expects(:find_by)
        .with({ owner: owner, repository_id: 0 }).returns(current_usage4)


      [current_usage1, current_usage3, current_usage4].each do |cu|
        cu.expects(:update_from_events!)
      end

      ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
    end

    test "it aggregates current usage records for the current owner_id if owner is gone" do
      billable_owner = create(:business)
      owner = create(:organization, business: billable_owner)
      repo1, repo2, repo3 = create_list(:repository, 3, owner: owner)
      current_usage1 = create(:shared_storage_current_usage, owner: owner, repository: repo1)
      current_usage3 = create(:shared_storage_current_usage, owner: owner, repository: repo3)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo1)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo2)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo3)

      cutoff = Time.current

      owner_id = owner.id
      owner.destroy!

      CurrentUsage.expects(:find_by)
        .with({ owner_id: owner_id, repository_id: repo1.id }).returns(current_usage1)
      CurrentUsage.expects(:find_by)
        .with({ owner_id: owner_id, repository_id: repo2.id }).returns(nil)
      CurrentUsage.expects(:find_by)
        .with({ owner_id: owner_id, repository_id: repo3.id }).returns(current_usage3)

      [current_usage1, current_usage3].each do |cu|
        cu.expects(:update_from_events!)
      end

      ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner_id).perform
    end

    test "if an owner cannot be found, it doesn't raise an exception nor send an email" do
      travel_to(GitHub::Billing.timezone.local(2019, 1, 31, 11, 59)) do
        owner = create(:credit_card_user)
        repo = create(:private_repository, owner: owner)
        cutoff = owner.current_metered_billing_cycle_starts_at + 14.days

        # Within current metered billing cycle, but 7 days before cutoff.
        aggregate_effective_at = owner.current_metered_billing_cycle_starts_at + 7.days

        # Owner has spending limit of $0.01
        create(:billing_budget, :enforce, owner: owner, spending_limit_in_subunits: 1)

        included_megabytes = owner.plan.shared_storage_included_megabytes.megabytes
        assumed_days = Billing::SharedStorage::ZuoraProduct::ASSUMED_MONTHLY_DAYS
        included_megabyte_hours = included_megabytes * assumed_days * 24

        # Included storage plus 100,000 - monthly storage exceeds monthly $0.01
        create(:shared_storage_artifact_event,
          :add_event,
          :private_visibility,
          repository: repo,
          effective_at: aggregate_effective_at,
          size_in_bytes: included_megabyte_hours + 100_000.megabytes,
        )

        # Using delete here because destroy would fire off the callbacks, one of which is to remove
        # all user notices records from KV. Unfortunately, with the time travel there are notices
        # that have not been decommisioned, but no longer have `hide_from_new_user` which causes
        # that particular callback to bomb.
        owner.delete

        assert_no_difference -> { ActionMailer::Base.deliveries.count } do
          ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
        end
      end
    end

    test "it performs all non-billing read queries against replicas" do
      billable_owner = create(:business)
      owner = create(:organization, business: billable_owner)
      repo1, repo2, repo3 = create_list(:repository, 3, owner: owner)

      Timecop.freeze(2.days.ago) do
        create(:shared_storage_current_usage, owner: owner, repository: repo1)
        create(:shared_storage_current_usage, owner: owner, repository: repo3)
        create(:shared_storage_current_usage, owner: owner, repository_id: 0)

        create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo1)
        create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo2)
        create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo3)
        create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: nil, owner: owner)
      end

      cutoff = Time.current

      _, queries = log_queries do
        ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
      end

      read_queries_against_primary = filter_primary_queries(queries)
        .select { |q| q.digested_sql.starts_with?("SELECT") }
        .reject { |q| q.digested_sql.ends_with?("FOR UPDATE") || q.digested_sql.include?("FROM shared_storage_artifact_events") }
      assert read_queries_against_primary.empty?, "Read queries against the primary were found: #{read_queries_against_primary.map(&:sql).join(', ')}"
    end

    test "enequeues a MeteredBillingThresholdNotifierJob" do
      current_hour = Time.current.beginning_of_hour
      owner = create(:credit_card_user)
      repo = create(:private_repository, owner: owner)
      current_usage = create(
        :shared_storage_current_usage,
        owner: owner,
        repository: repo,
        effective_at: current_hour - 2.hours
      )

      assert_enqueued_with job: MeteredBillingThresholdNotifierJob do
        ArtifactEventAggregator.new(cutoff: current_hour, owner_id: owner.id).perform
      end
    end

    test "it skips aggregation if the billable owner is onboarded to action in billing platform and feature is enabled" do
      GitHub.flipper[:actions_storage_migration_skip].enable
      GitHub.flipper[:actions_storage_usage_dual_emit_to_meuse_and_vnext].disable

      billable_owner = create(:business)
      owner = create(:organization, business: billable_owner)
      repo = create(:repository, owner: owner)
      current_usage1 = create(:shared_storage_current_usage, owner: owner, repository: repo)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo)

      billable_owner.customer.update!(billed_via_billing_platform: true)
      create :billing_platform_enabled_product, :actions_enabled, customer: billable_owner.customer

      cutoff = Time.current

      CurrentUsage.expects(:find_by).never
      current_usage1.expects(:update_from_events!).never

      ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
    end

    test "it aggregates if the billable owner is in 'actions_storage_usage_dual_emit_to_meuse_and_vnext' feature flag" do
      billable_owner = create(:business)
      GitHub.flipper[:actions_storage_usage_dual_emit_to_meuse_and_vnext].enable(billable_owner)

      owner = create(:organization, business: billable_owner)
      repo = create(:repository, owner: owner)
      current_usage1 = create(:shared_storage_current_usage, owner: owner, repository: repo)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo)

      billable_owner.customer.update!(billed_via_billing_platform: true)
      create :billing_platform_enabled_product, :actions_enabled, customer: billable_owner.customer

      cutoff = Time.current

      CurrentUsage.expects(:find_by).with({ owner: owner, repository_id: repo.id }).returns(current_usage1)
      current_usage1.expects(:update_from_events!)

      ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
    end

    test "it skips aggregation if the billable owner is not in 'actions_storage_usage_dual_emit_to_meuse_and_vnext' feature flag" do
      billable_owner = create(:business)
      billable_owner.customer.update!(billed_via_billing_platform: true)
      create :billing_platform_enabled_product, :actions_enabled, customer: billable_owner.customer
      GitHub.flipper[:actions_storage_usage_dual_emit_to_meuse_and_vnext].disable
      GitHub.flipper[:actions_storage_migration_skip].enable

      owner = create(:organization, business: billable_owner)
      repo = create(:repository, owner: owner)
      current_usage1 = create(:shared_storage_current_usage, owner: owner, repository: repo)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo)

      cutoff = Time.current

      CurrentUsage.expects(:find_by).never
      current_usage1.expects(:update_from_events!).never

      ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
    end

    test "aggregates if the migration feature flag is disabled" do
      GitHub.flipper[:actions_storage_migration_skip].disable

      billable_owner = create(:business)
      owner = create(:organization, business: billable_owner)
      repo = create(:repository, owner: owner)
      current_usage1 = create(:shared_storage_current_usage, owner: owner, repository: repo)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo)

      cutoff = Time.current

      CurrentUsage.expects(:find_by).with({ owner: owner, repository_id: repo.id }).returns(current_usage1)
      current_usage1.expects(:update_from_events!)

      ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
    end

    test "it skips aggregation if the billable owner is in the 'skip_shared_storage_aggregation' feature flag" do
      billable_owner = create(:business)
      GitHub.flipper[:skip_shared_storage_aggregation].enable(billable_owner)

      owner = create(:organization, business: billable_owner)
      repo = create(:repository, owner: owner)
      current_usage1 = create(:shared_storage_current_usage, owner: owner, repository: repo)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo)

      cutoff = Time.current

      CurrentUsage.expects(:find_by).never
      current_usage1.expects(:update_from_events!).never

      ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
    end

    test "aggregates if 'skip_shared_storage_aggregation' feature flag is disabled" do
      GitHub.flipper[:skip_shared_storage_aggregation].disable

      billable_owner = create(:business)
      owner = create(:organization, business: billable_owner)
      repo = create(:repository, owner: owner)
      current_usage1 = create(:shared_storage_current_usage, owner: owner, repository: repo)
      create(:shared_storage_artifact_event, :add_event, :public_visibility, repository: repo)

      cutoff = Time.current

      CurrentUsage.expects(:find_by).with({ owner: owner, repository_id: repo.id }).returns(current_usage1)
      current_usage1.expects(:update_from_events!)

      ArtifactEventAggregator.new(cutoff: cutoff, owner_id: owner.id).perform
    end
  end
end if GitHub.billing_enabled?
