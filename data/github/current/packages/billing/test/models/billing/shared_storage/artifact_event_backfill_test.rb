# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::SharedStorage
  class ArtifactEventBackfillTest < GitHub::TestCase
    include ::Billing::ApiTestHelpers
    include GitHub::LoggerHelper
    include HydroTestHelpers

    test "events for a User/Org" do
      enable_feature_flag(:artifact_event_backfill_migration)

      @billable_owner = create(:user, :zuora)
      @owner = @billable_owner
      @repo = create(:repository, owner: @billable_owner)
      @repo_2 = create(:repository, owner: @billable_owner)
      @billable_owner.customer.update!(billed_via_billing_platform: true)
      create :billing_platform_enabled_product, :actions_enabled, customer: @billable_owner.customer

      now = Time.now.utc.beginning_of_day

      # Create events that are from today.
      Timecop.freeze(now) do
        create(:shared_storage_current_usage, :public_visibility, owner: @owner, repository: @repo,)
        create(:shared_storage_current_usage, :public_visibility, owner: @owner, repository: @repo_2,)

        @artifact_add = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        @artifact_remove = create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        @artifact_add_other_repo = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repo_2,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        _future_removal_event = create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          effective_at: now + 1.day,
          repository: @repo_2,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
      end

      # Create events that are from yesterday.
      # Note: the CurrentUsage records were already creaetd above and we use CurrentUsage to determine which
      # artifact events to backfill.
      Timecop.freeze(now - 1.day) do
        create(
         :shared_storage_artifact_event, :add_event, :private_visibility,
         repository: @repo,
         source: "actions",
         size_in_bytes: 2.gigabyte
       )
        create(
         :shared_storage_artifact_event, :remove_event, :private_visibility,
         repository: @repo,
         source: "actions",
         size_in_bytes: 1.gigabyte
       )
        create(
         :shared_storage_artifact_event, :add_event, :private_visibility,
         repository: @repo_2,
         source: "actions",
         size_in_bytes: 1.gigabyte
       )
      end

      backfill = Billing::SharedStorage::ArtifactEventBackfill.new(billable_owner: @billable_owner, cutoff: now)

      Timecop.freeze(now) { backfill.perform }

      assert_hydro_messages(count: 5, schema: "billingplatform.v1.Usage")

      # Assert that the individual events are all emitted
      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: @artifact_add.to_global_id.to_s,
        usage_at: @artifact_add.created_at.change(usec: 0),
        usage_uuid: build_uuid("Actions/#{@artifact_add.source_artifact_id}/add"),
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: @owner.id,
          repo_id: @repo.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_hydro_published({
        sku: "actions_storage",
        quantity: -1.0,
        source_uri: @artifact_remove.to_global_id.to_s,
        usage_at: @artifact_remove.created_at.change(usec: 0),
        usage_uuid: build_uuid("Actions/#{@artifact_remove.source_artifact_id}/remove"),
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: @owner.id,
          repo_id: @repo.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: @artifact_add_other_repo.to_global_id.to_s,
        usage_at: @artifact_add_other_repo.created_at.change(usec: 0),
        usage_uuid: build_uuid("Actions/#{@artifact_add_other_repo.source_artifact_id}/add"),
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: @owner.id,
          repo_id: @repo_2.id,
        }
      }, schema: "billingplatform.v1.Usage")

      # Assert that the aggregate events are emitted
      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: "Actions/aggregate-backfill/#{@owner.id}/#{@repo.id}",
        usage_at: (now.utc.beginning_of_day - 1.day),
        usage_uuid: build_uuid("Actions/backfill/#{@owner.id}/#{@repo.id}"),
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: @owner.id,
          repo_id: @repo.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: "Actions/aggregate-backfill/#{@owner.id}/#{@repo_2.id}",
        usage_at: (now.utc.beginning_of_day - 1.day),
        usage_uuid: build_uuid("Actions/backfill/#{@owner.id}/#{@repo_2.id}"),
        entity: {
          customer_id: @billable_owner.customer.id,
          organization_id: @owner.id,
          repo_id: @repo_2.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_equal(
        Billing::Kv.store.get("billing_platform_migration.backfill_completed_at.#{@billable_owner.customer.id}").value { nil },
        now.iso8601
      )
    end

    test "events for a Business" do
      enable_feature_flag(:artifact_event_backfill_migration)

      @business = create(:business)
      @org = create(:organization, business: @business)
      @repo = create(:repository, owner: @org)
      @repo_2 = create(:repository, owner: @org)
      @other_org = create(:organization, business: @business)
      @other_org_repo = create(:repository, owner: @other_org)
      @business.customer.update!(billed_via_billing_platform: true)
      create :billing_platform_enabled_product, :actions_enabled, customer: @business.customer

      now = Time.now.utc.beginning_of_day

      # Create events that are from today.
      Timecop.freeze(now) do
        create(:shared_storage_current_usage, :public_visibility, owner: @org, repository: @repo,)
        create(:shared_storage_current_usage, :public_visibility, owner: @org, repository: @repo_2,)
        create(:shared_storage_current_usage, :public_visibility, owner: @other_org, repository: @other_org_repo,)

        @artifact_add = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        @artifact_remove = create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        @artifact_add_other_repo = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repo_2,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        @other_org_artifact_add = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @other_org_repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        _future_removal_event = create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          effective_at: now + 1.day,
          repository: @repo_2,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
      end

      # Create events that are from yesterday.
      # Note: the CurrentUsage records were already creaetd above and we use CurrentUsage to determine which
      # artifact events to backfill.
      Timecop.freeze(now - 1.day) do
        create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 2.gigabyte
        )
        create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repo_2,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @other_org_repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
      end

      backfill = Billing::SharedStorage::ArtifactEventBackfill.new(billable_owner: @business)

      Timecop.freeze(now) { backfill.perform }

      assert_hydro_messages(count: 7, schema: "billingplatform.v1.Usage")

      # Assert that the individual events are all emitted
      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: @artifact_add.to_global_id.to_s,
        usage_at: @artifact_add.created_at.change(usec: 0),
        usage_uuid: build_uuid("Actions/#{@artifact_add.source_artifact_id}/add"),
        entity: {
          customer_id: @business.customer.id,
          organization_id: @org.id,
          repo_id: @repo.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_hydro_published({
        sku: "actions_storage",
        quantity: -1.0,
        source_uri: @artifact_remove.to_global_id.to_s,
        usage_at: @artifact_remove.created_at.change(usec: 0),
        usage_uuid: build_uuid("Actions/#{@artifact_remove.source_artifact_id}/remove"),
        entity: {
          customer_id: @business.customer.id,
          organization_id: @org.id,
          repo_id: @repo.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: @artifact_add_other_repo.to_global_id.to_s,
        usage_at: @artifact_add_other_repo.created_at.change(usec: 0),
        usage_uuid: build_uuid("Actions/#{@artifact_add_other_repo.source_artifact_id}/add"),
        entity: {
          customer_id: @business.customer.id,
          organization_id: @org.id,
          repo_id: @repo_2.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: @other_org_artifact_add.to_global_id.to_s,
        usage_at: @other_org_artifact_add.created_at.change(usec: 0),
        usage_uuid: build_uuid("Actions/#{@other_org_artifact_add.source_artifact_id}/add"),
        entity: {
          customer_id: @business.customer.id,
          organization_id: @other_org.id,
          repo_id: @other_org_repo.id,
        }
      }, schema: "billingplatform.v1.Usage")

      # Assert that the aggregate events are emitted
      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: "Actions/aggregate-backfill/#{@org.id}/#{@repo.id}",
        usage_at: (now.utc.beginning_of_day - 1.day),
        usage_uuid: build_uuid("Actions/backfill/#{@org.id}/#{@repo.id}"),
        entity: {
          customer_id: @business.customer.id,
          organization_id: @org.id,
          repo_id: @repo.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: "Actions/aggregate-backfill/#{@org.id}/#{@repo_2.id}",
        usage_at: (now.utc.beginning_of_day - 1.day),
        usage_uuid: build_uuid("Actions/backfill/#{@org.id}/#{@repo_2.id}"),
        entity: {
          customer_id: @business.customer.id,
          organization_id: @org.id,
          repo_id: @repo_2.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_hydro_published({
        sku: "actions_storage",
        quantity: 1.0,
        source_uri: "Actions/aggregate-backfill/#{@other_org.id}/#{@other_org_repo.id}",
        usage_at: (now.utc.beginning_of_day - 1.day),
        usage_uuid: build_uuid("Actions/backfill/#{@other_org.id}/#{@other_org_repo.id}"),
        entity: {
          customer_id: @business.customer.id,
          organization_id: @other_org.id,
          repo_id: @other_org_repo.id,
        }
      }, schema: "billingplatform.v1.Usage")

      assert_equal(
        Billing::Kv.store.get("billing_platform_migration.backfill_completed_at.#{@business.customer.id}").value { nil },
        now.iso8601
      )
    end

    test "duplicate removal events that result in negative sum are dismissed" do
      enable_feature_flag(:artifact_event_backfill_migration)

      @billable_owner = create(:user, :zuora)
      @owner = @billable_owner
      @repo = create(:repository, owner: @billable_owner)
      @billable_owner.customer.update!(billed_via_billing_platform: true)
      create :billing_platform_enabled_product, :actions_enabled, customer: @billable_owner.customer

      now = Time.now.utc.beginning_of_day

      # Create events that are from yesterday.
      Timecop.freeze(now - 1.day) do
        create(:shared_storage_current_usage, :public_visibility, owner: @owner, repository: @repo,)
        create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
        create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          repository: @repo,
          source: "actions",
          size_in_bytes: 1.gigabyte
        )
      end

      backfill = Billing::SharedStorage::ArtifactEventBackfill.new(billable_owner: @billable_owner, cutoff: now)

      Timecop.freeze(now) { backfill.perform }

      refute_hydro_messages(schema: "billingplatform.v1.Usage")
    end

    test "raises an error when the billable owner has already been migrated" do
      billable_owner = create(:user, :zuora)
      billable_owner.customer.update!(billed_via_billing_platform: true)
      create :billing_platform_enabled_product, :actions_enabled, customer: billable_owner.customer

      Billing::Kv.store.set("billing_platform_migration.backfill_completed_at.#{billable_owner.customer.id}", Time.now.utc.iso8601)

      assert_raises_with_message(ArgumentError, "Billable owner has already been migrated") do
        Billing::SharedStorage::ArtifactEventBackfill.new(billable_owner: billable_owner)
      end
    end

    test "raises an error if the billable owner is not flagged for migration" do
      billable_owner = create(:user, :zuora)

      assert_raises_with_message(ArgumentError, "Billable owner is not eligible for a migration") do
        Billing::SharedStorage::ArtifactEventBackfill.new(billable_owner: billable_owner)
      end
    end

    test "raises an error if the billable owner is missing a customer" do
      billable_owner = create(:user)

      assert_raises_with_message(ArgumentError, "Billable owner does not have a customer") do
        Billing::SharedStorage::ArtifactEventBackfill.new(billable_owner: billable_owner)
      end
    end

    def build_uuid(string)
      Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, string) # rubocop:disable GitHub/InsecureHashAlgorithm
    end
  end

end if GitHub.billing_enabled?
