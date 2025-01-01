# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::SharedStorage
  class CurrentUsageTest < GitHub::TestCase
    include GitHub::LoggerHelper
    include HydroTestHelpers

    fixtures do
      @repository = create(:repository)
      @owner = @repository.owner
      @billable_owner = @owner.billable_owner
    end

    context "validations" do
      [
        [:owner_id, :owner],
        [:repository_id, :repository],
        [:billable_owner_id, :billable_owner]
      ].each do |field_id, field|
        test "#{field_id} is valid even if #{field} has been deleted" do
          usage = Billing::SharedStorage::CurrentUsage.new(field_id => -1)
          usage.valid?

          assert_empty usage.errors[field_id]
          assert_empty usage.errors[field]
        end
      end

      [:owner_id, :repository_id, :aggregate_size_in_bytes].each do |field|
        test "#{field} is required" do
          error = assert_raises ActiveRecord::RecordInvalid do
            create(:shared_storage_current_usage, field => nil)
          end

          assert_equal "Validation failed: #{field.to_s.humanize} can't be blank", error.message
        end
      end

      test "owner_id, repository_id combination must be unique" do
        existing_usage = create(:shared_storage_current_usage)

        assert_raises ActiveRecord::RecordNotUnique do
          create(
            :shared_storage_current_usage,
            owner_id: existing_usage.owner_id,
            repository_id: existing_usage.repository_id
          )
        end
      end
    end

    context "scopes" do
      context "for_reporting" do
        test "returns current usage for reporting" do
          owner = create(:user)
          usage = create(:shared_storage_current_usage,
                        owner: owner, billable_owner: owner,
                        repository_visibility: "private")

          for_reporting = Billing::SharedStorage::CurrentUsage.for_reporting(
            billable_owner: owner.billable_owner,
            owner_id: owner.id,
            repository_visibility: "private"
          )
          assert_equal [usage], for_reporting
        end

        test "returns usage for entire enterprise" do
          business = create(:business)
          org1 = create(:enterprise_linked_organization, business: business)
          org2 = create(:enterprise_linked_organization, business: business)
          usage1 = create(:shared_storage_current_usage,
                          owner: org1, billable_owner: business,
                          repository_visibility: "private")
          usage2 = create(:shared_storage_current_usage,
                          owner: org2, billable_owner: business,
                          repository_visibility: "private")

          for_reporting = Billing::SharedStorage::CurrentUsage.for_reporting(
            billable_owner: business,
            repository_visibility: "private"
          ).to_a
          # Order by :id to assure deterministic test results
          assert_equal [usage1, usage2], for_reporting.sort_by { T.must(_1.id) }
        end

        test "returns usage for specific org in an enterprise" do
          business = create(:business)
          org1 = create(:enterprise_linked_organization, business: business)
          org2 = create(:enterprise_linked_organization, business: business)
          usage1 = create(:shared_storage_current_usage,
                          owner: org1, billable_owner: business,
                          repository_visibility: "private")
          usage2 = create(:shared_storage_current_usage,
                          owner: org2, billable_owner: business,
                          repository_visibility: "private")

          for_reporting = Billing::SharedStorage::CurrentUsage.for_reporting(
            billable_owner: business,
            owner_id: org2.id,
            repository_visibility: "private"
          )
          assert_equal [usage2], for_reporting
        end

        test "defaults visibility to private" do
          owner = create(:user)
          usage = create(:shared_storage_current_usage,
                        owner: owner, billable_owner: owner,
                        repository_visibility: "private")

          for_reporting = Billing::SharedStorage::CurrentUsage.for_reporting(
            billable_owner: owner.billable_owner,
            owner_id: owner.id,
          )
          assert_equal [usage], for_reporting
        end

        test "does not query on owner if not provided" do
          owner = create(:user)
          usage = create(:shared_storage_current_usage, billable_owner: owner,
                        repository_visibility: "private")

          for_reporting = Billing::SharedStorage::CurrentUsage.for_reporting(
            billable_owner: owner,
            repository_visibility: "private"
          )

          refute_match(/`shared_storage_usage`\.`owner_id`/, for_reporting.to_sql)
          assert_equal [usage], for_reporting
        end
      end
    end

    context "#to_meuse" do
      test "returns a hash ready to be sent to Meuse" do
        usage = create(:shared_storage_current_usage)

        expected_keys = [
          :usage_uuid, :product_name, :product_sku_name, :usage_at, :quantity,
          :account_id, :source_uri, :custom_fields
        ]

        meuse_request = usage.to_meuse
        assert_equal expected_keys.sort, meuse_request.keys.sort
        assert_equal 10.megabytes, meuse_request[:quantity]
        assert_equal ["repository.id"], meuse_request[:custom_fields].keys
        assert_equal "shared_storage", meuse_request[:product_name]
        assert_equal "default", meuse_request[:product_sku_name]
      end
    end

    context "#reportable_to_meuse?" do
      test "returns true for private visibility and positive size in bytes" do
        usage = create(:shared_storage_current_usage, :private_visibility, aggregate_size_in_bytes: 100)

        assert usage.reportable_to_meuse?
      end

      test "returns false for public visibility" do
        usage = create(:shared_storage_current_usage, :public_visibility)

        assert_not usage.reportable_to_meuse?
      end

      test "returns false for 0 size in bytes" do
        usage = create(:shared_storage_current_usage, :private_visibility, aggregate_size_in_bytes: 0)

        assert_not usage.reportable_to_meuse?
      end
    end

    context "#rebuild_from_events!" do
      test "fixes a mismatched aggregation" do
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 1.megabytes,
          effective_at: Time.current
        )
        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 100.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 50.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 10.megabytes, effective_at: 1.day.from_now)
        agg.rebuild_from_events!

        assert_equal(50.megabytes, agg.reload.aggregate_size_in_bytes)
      end

      test "associates Event's repo_id:nil or 0 with usage's repo_id: 0" do
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository_id: 0,
          aggregate_size_in_bytes: 1.megabytes,
          effective_at: Time.current
        )
        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          owner: @owner, repository_id: nil, size_in_bytes: 100.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        event = create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
          owner: @owner, repository_id: nil, size_in_bytes: 50.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)

        event.repository_id = 0
        event.save!(validate: false)

        agg.rebuild_from_events!

        assert_equal(50.megabytes, agg.reload.aggregate_size_in_bytes)
      end

      test "treats negative sums as 0" do
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 1.megabytes,
          effective_at: Time.current
        )

        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 100.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 50.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 10.megabytes, effective_at: 1.day.from_now)
        create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 150.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)

        agg.rebuild_from_events!

        assert_equal(0.megabytes, agg.reload.aggregate_size_in_bytes)
      end

      test "logs the mismatch" do
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 1.megabytes,
          effective_at: Time.current
        )
        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 100.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 50.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 10.megabytes, effective_at: 1.day.from_now)

        expected_log = {
          "Body": "SharedStorage size mismatch",
          "code.namespace": "Billing::SharedStorage::CurrentUsage",
          "gh.billing.current_usage.owner.id": @owner.id,
          "gh.repo.id": @repository.id,
          "gh.billing.current_usage.id": agg.id,
          "gh.billing.current_usage.old_size": 1.megabytes,
          "gh.billing.current_usage.new_size": 50.megabytes,
        }

        assert_logged(**expected_log) do
          agg.rebuild_from_events!
        end
      end

      test "No updates on match" do
        agg = create(
          :shared_storage_current_usage,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 50.megabytes,
          effective_at: Time.current
        )
        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 100.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 50.megabytes, effective_at: 2.days.ago, aggregation_id: agg.id)
        create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
          repository: @repository, size_in_bytes: 10.megabytes, effective_at: 1.day.from_now)


        assert_no_changes -> { agg.reload.updated_at } do
          agg.rebuild_from_events!
        end
      end
    end

    context "update_from_events_through!" do

      test "does nothing if the cutoff is earlier than the current effective at" do
        current_hour = Time.current.beginning_of_hour

        current_usage = create(
          :shared_storage_current_usage, :public_visibility,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 20,
          effective_at: current_hour
        )

        current_usage.update_from_events_through!(cutoff: current_hour - 1.hour, start: (current_hour - 2.hours).beginning_of_hour)

        ArtifactEvent.expects(:where).never
        CurrentUsage.any_instance.expects(:update!).never
      end

      context "when there are new events" do
        test "updates existing usage record" do
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          events = Timecop.freeze(1.hour.ago) do
            [
              create(
                :shared_storage_artifact_event, :add_event, :public_visibility,
                repository: @repository,
                size_in_bytes: 10
              ),
              create(
                :shared_storage_artifact_event, :remove_event, :public_visibility,
                repository: @repository,
                size_in_bytes: 2
              ),
              create(
                :shared_storage_artifact_event, :unknown_event, :public_visibility,
                repository: @repository,
                size_in_bytes: 3
              ),
            ]
          end

          assert_no_difference(-> { CurrentUsage.count }) do
            current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)
          end

          assert_equal @owner, current_usage.owner
          assert_equal @billable_owner, current_usage.billable_owner
          assert_equal "public", current_usage.repository_visibility
          # 20 previous + 10 added - 2 removed
          # Unknown event (3 bytes) is ignored

          assert_equal 28, current_usage.aggregate_size_in_bytes

          events.each do |event|
            assert event.reload.aggregated?
          end
        end

        test "associates Event's repo_id:nil with usage's repo_id: 0" do
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository_id: 0,
              aggregate_size_in_bytes: 20
            )
          end

          events = Timecop.freeze(1.hour.ago) do
            [
              create(
                :shared_storage_artifact_event, :add_event, :public_visibility,
                owner: @owner,
                repository: nil,
                size_in_bytes: 10
              ),
              create(
                :shared_storage_artifact_event, :remove_event, :public_visibility,
                owner: @owner,
                repository: nil,
                size_in_bytes: 2
              ),
              create(
                :shared_storage_artifact_event, :unknown_event, :public_visibility,
                owner: @owner,
                repository: nil,
                size_in_bytes: 3
              ),
            ]
          end

          event = events[1]
          event.repository_id = 0
          event.save!(validate: false)

          assert_no_difference(-> { CurrentUsage.count }) do
            current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)
          end

          assert_equal @owner, current_usage.owner
          assert_equal @billable_owner, current_usage.billable_owner
          assert_equal "public", current_usage.repository_visibility
          # 20 previous + 10 added - 2 removed
          # Unknown event (3 bytes) is ignored

          assert_equal 28, current_usage.aggregate_size_in_bytes

          events.each do |event|
            assert event.reload.aggregated?
          end
        end

        test "aggregates to zero when shared storage has been removed" do
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :remove_event, :public_visibility,
              owner: @owner,
              repository: @repository,
              size_in_bytes: 20
            )
          end

          assert_no_difference(-> { CurrentUsage.count }) do
            current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)
          end

          assert_equal @owner, current_usage.owner
          assert_equal @billable_owner, current_usage.billable_owner
          assert_equal "public", current_usage.repository_visibility
          assert_equal 0, current_usage.aggregate_size_in_bytes
        end

        test "sets the aggregate_size_in_bytes to zero if it sums to a negative number" do
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          travel_to(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :remove_event, :public_visibility,
              repository: @repository,
              size_in_bytes: 20_000
            )
          end

          current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)

          assert_equal 0, current_usage.aggregate_size_in_bytes
        end

        test "does not aggregate events effective in the future" do
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          future_event = Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :public_visibility,
              repository: @repository,
              size_in_bytes: 20,
              effective_at: 90.days.from_now
            )
          end

          assert_no_difference(-> { CurrentUsage.count }) do
            current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)
          end

          assert_nil future_event.reload.aggregation_id
        end

        test "does not aggregate events that are already aggregated" do
          current_usage = T.let(nil, T.nilable(Billing::SharedStorage::CurrentUsage))

          Timecop.freeze(2.hours.ago) do
            current_usage = create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
            create(
              :shared_storage_artifact_event, :add_event, :public_visibility,
              owner: @owner,
              repository: @repository,
              size_in_bytes: 30,
              aggregation_id: CurrentUsage::EVENT_AGGREGATION_ID
            )
          end

          Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :public_visibility,
              owner: @owner,
              repository: @repository,
              size_in_bytes: 20
            )
          end

          current_usage = T.must(current_usage)

          assert_no_difference(-> { CurrentUsage.count }) do
            current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)
          end

          # 20 previous aggregation + 20 added
          assert_equal 40, current_usage.reload.aggregate_size_in_bytes
        end

        test "increments metrics" do
          stats = GitHub::MemoryDogstatsD.new
          GitHub.stubs(:dogstats).returns(stats)

          current_usage = T.let(nil, T.nilable(Billing::SharedStorage::CurrentUsage))

          Timecop.freeze(1.hour.ago) do
            current_usage = create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
            [
              create(
                :shared_storage_artifact_event, :add_event, :public_visibility,
                repository: @repository,
                size_in_bytes: 10
              ),
              create(
                :shared_storage_artifact_event, :remove_event, :public_visibility,
                repository: @repository,
                size_in_bytes: 2
              ),
              create(
                :shared_storage_artifact_event, :unknown_event, :public_visibility,
                repository: @repository,
                size_in_bytes: 3
              ),
            ]
          end

          T.must(current_usage).update_from_events_through!(
            cutoff: Time.now, start: 1.hour.ago.beginning_of_hour
          )

          assert_equal 1, stats.increments("billing.shared_storage.repositories_aggregated").length
          assert_equal 1, stats.counts("billing.shared_storage.events_aggregated").length
          assert_equal 3, stats.counts("billing.shared_storage.events_aggregated").first.value
        end

        test "sends usage directly to meuse for private visibility usage" do
          disable_feature_flag(:billing_large_event_windows)
          @repository.update!(public: false)

          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 0
            )
          end

          Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :private_visibility,
              repository: @repository,
              size_in_bytes: 10
            )
          end

          current_usage.update_from_events_through!(cutoff: Time.now, start: 1.hour.ago.beginning_of_hour)

          hydro_payload = hydro_messages(schema: "meuse.v0.MeteredUsage").first

          assert_equal 10, hydro_payload[:quantity]
          assert_equal @owner.id, hydro_payload[:account_id]
          assert_nil hydro_payload[:actor_id]
          assert hydro_payload[:usage_at].present?
          assert_match /CurrentUsage/, hydro_payload[:source_uri]
          assert_equal @repository.id.to_s, hydro_payload.dig(:custom_fields, "repository.id")
        end

        test "does not send usage to Meuse for public visibility usage" do
          @repository.update!(public: true)

          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :public_visibility,
              repository: @repository,
              size_in_bytes: 10
            )
          end

          current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)

          refute_hydro_messages(schema: "meuse.v0.MeteredUsage")
        end

        test "does not send usage to Meuse for aggregations with a size of zero" do
          @repository.update!(public: false)

          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 0
            )
          end

          Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :private_visibility,
              repository: @repository,
              size_in_bytes: 10
            )
            create(
              :shared_storage_artifact_event, :remove_event, :private_visibility,
              repository: @repository,
              size_in_bytes: 10
            )
          end
          current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)

          refute_hydro_messages(schema: "meuse.v0.MeteredUsage")
        end

        test "updates usage using the repository's current visibility" do
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner, repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :public_visibility,
              repository: @repository, size_in_bytes: 10
            )
          end

          # Previous aggregation and events are public and repo is now private
          Repository.where(id: @repository.id).update_all(public: false)

          assert_no_difference(-> { CurrentUsage.count }) do
            current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)
          end

          # Private visibility based on current repository state
          assert_equal "private", current_usage.repository_visibility
        end

        test "sends correct usage quanity for large event windows" do
          enable_feature_flag(:billing_large_event_windows)

          @repository.update!(public: false)
          current_usage = Timecop.freeze(13.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 0,
              effective_at: Time.now
            )
          end

          prior_effective_at = current_usage.effective_at.beginning_of_hour

          Timecop.freeze(12.hours.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :private_visibility,
              repository: @repository,
              size_in_bytes: 10,
            )
          end

          current_usage.update_from_events_through!(cutoff: prior_effective_at + CurrentUsage::LARGE_EVENT_WINDOW_HOURS.hours, start: prior_effective_at)

          hydro_payload = hydro_messages(schema: "meuse.v0.MeteredUsage").first

          expected_quantity = 10 * Billing::SharedStorage::CurrentUsage::LARGE_EVENT_WINDOW_HOURS

          assert_equal expected_quantity, hydro_payload[:quantity]
          assert_equal @owner.id, hydro_payload[:account_id]
          assert_nil hydro_payload[:actor_id]
          assert hydro_payload[:usage_at].present?
          assert_match /CurrentUsage/, hydro_payload[:source_uri]
          assert_equal @repository.id.to_s, hydro_payload.dig(:custom_fields, "repository.id")
        end

        test "sends correct usage quanity for large event windows that are cropped by the current time" do
          enable_feature_flag(:billing_large_event_windows)
          # note, this is unlikley to happen due to the:
          #
          # max_cutoff = Time.current.beginning_of_hour
          # if destroyed? || prior_effective_at + (update_event_window - 1.hour) >= max_cutoff || windows_processed >= MAX_WINDOWS_TO_AGGREGATE
          #
          # gate in update_from_events!

          @repository.update!(public: false)
          current_usage = Timecop.freeze(5.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 0,
              effective_at: Time.now
            )
          end

          prior_effective_at = current_usage.effective_at.beginning_of_hour

          Timecop.freeze(4.hours.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :private_visibility,
              repository: @repository,
              size_in_bytes: 10
            )
          end

          current_usage.update_from_events_through!(cutoff: prior_effective_at + CurrentUsage::LARGE_EVENT_WINDOW_HOURS.hours, start: prior_effective_at)

          hydro_payload = hydro_messages(schema: "meuse.v0.MeteredUsage").first

          assert_equal 50, hydro_payload[:quantity] # 10 * 5 hours
          assert_equal @owner.id, hydro_payload[:account_id]
          assert_nil hydro_payload[:actor_id]
          assert hydro_payload[:usage_at].present?
          assert_match /CurrentUsage/, hydro_payload[:source_uri]
          assert_equal @repository.id.to_s, hydro_payload.dig(:custom_fields, "repository.id")
        end
      end

      context "when there are no new events" do
        test "updates usage" do
          current_usage = T.let(nil, T.nilable(Billing::SharedStorage::CurrentUsage))

          Timecop.freeze(1.day.ago) do
            current_usage = create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner, repository: @repository,
              effective_at: Time.now.beginning_of_day,
              aggregate_size_in_bytes: 20
            )

            create(
              :shared_storage_artifact_event, :add_event, :public_visibility,
              repository: @repository,
              size_in_bytes: 20,
              aggregation_id: current_usage.id
            )
          end

          now = Time.now
          current_usage = T.must(current_usage)
          current_usage.update_from_events_through!(cutoff: now, start: 1.hour.ago.beginning_of_hour)

          assert_equal now.beginning_of_hour, current_usage.effective_at
        end

        test "sends usage to Meuse" do
          disable_feature_flag(:billing_large_event_windows)
          @repository.update!(public: false)
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :private_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          current_usage.update_from_events_through!(cutoff: Time.now, start: 1.hour.ago.beginning_of_hour)

          hydro_payload = hydro_messages(schema: "meuse.v0.MeteredUsage").first

          assert_equal "shared_storage", hydro_payload[:product_name]
          assert_equal "default", hydro_payload[:product_sku_name]
          assert_equal 20, hydro_payload[:quantity]
          assert_equal @owner.id, hydro_payload[:account_id]
          assert_nil hydro_payload[:actor_id]
          assert hydro_payload[:usage_at].present?
          refute_nil hydro_payload[:usage_uuid]
          assert_match /CurrentUsage/, hydro_payload[:source_uri]
          assert_equal @repository.id.to_s, hydro_payload.dig(:custom_fields, "repository.id")
        end
      end

      context "when there are no events and usage is 0" do
        test "it updates the effective_at" do
          current_usage = Timecop.freeze(1.day.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner, repository: @repository,
              effective_at: Time.now.beginning_of_day,
              aggregate_size_in_bytes: 20
            )
          end

          now = Time.current
          beginning_of_hour = now.beginning_of_hour

          current_usage.update_from_events_through!(cutoff: now, start: 1.day.ago.beginning_of_hour)

          assert_equal beginning_of_hour, current_usage.effective_at
        end
      end

      context "Non-active repository" do
        test "updates the visibility from an archived repo" do
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          event = Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :public_visibility,
              repository: @repository,
              size_in_bytes: 10
            )
          end

          @repository.update!(public: false)
          @repository.remove(@repository.owner, synchronous: true)

          current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)

          assert_equal "private",  current_usage.repository_visibility
          # Previous aggregation is 20 + 10 added
          assert_equal 30, current_usage.aggregate_size_in_bytes
          assert event.reload.aggregated?
        end

        test "updates the visibility using latest event visibility if no active or archive repository exists" do
          current_usage = Timecop.freeze(2.hours.ago) do
            create(
              :shared_storage_current_usage, :public_visibility,
              owner: @owner,
              repository: @repository,
              aggregate_size_in_bytes: 20
            )
          end

          event = Timecop.freeze(1.hour.ago) do
            create(
              :shared_storage_artifact_event, :add_event, :private_visibility,
              repository: @repository,
              size_in_bytes: 10
            )
          end

          @repository.destroy!

          current_usage.update_from_events_through!(cutoff: Time.now, start: 2.hours.ago.beginning_of_hour)

          assert_equal "private", current_usage.repository_visibility
          assert_equal 30, current_usage.aggregate_size_in_bytes
          assert event.reload.aggregated?
        end
      end

      context "self destruction" do
        context "when owner is nil" do
          test "marks events as processed with special id" do
            @repository.update!(public: false)
            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            events = Timecop.freeze(1.hour.ago) do
              [
                create(
                  :shared_storage_artifact_event, :add_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 10
                ),
                create(
                  :shared_storage_artifact_event, :remove_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 2
                ),
                create(
                  :shared_storage_artifact_event, :unknown_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 3
                ),
              ]
            end

            @owner.destroy!
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)

            events.each do |event|
              assert_equal CurrentUsage::ORPHANED_EVENT_AGGREGATION_ID, event.reload.aggregation_id
            end
          end

          test "records metrics" do
            @repository.update!(public: false)
            stats = GitHub::MemoryDogstatsD.new
            GitHub.stubs(:dogstats).returns(stats)

            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            Timecop.freeze(1.hour.ago) do
              [
                create(
                  :shared_storage_artifact_event, :add_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 10
                ),
                create(
                  :shared_storage_artifact_event, :remove_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 2
                ),
                create(
                  :shared_storage_artifact_event, :unknown_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 3
                ),
              ]
            end

            @owner.destroy!
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)

            assert_equal 1, stats.increments("billing.shared_storage.aggregate_repositories_skipped", tags: ["reason:missing_owner"]).length
          end

          test "destroys itself and sends no usage" do
            @repository.update!(public: false)
            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            Timecop.freeze(1.hour.ago) do
              [
                create(
                  :shared_storage_artifact_event, :add_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 10
                ),
                create(
                  :shared_storage_artifact_event, :remove_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 2
                ),
                create(
                  :shared_storage_artifact_event, :unknown_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 3
                ),
              ]
            end

            @owner.destroy!
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_raises(ActiveRecord::RecordNotFound) do
              current_usage.reload
            end

            refute_hydro_messages(schema: "meuse.v0.MeteredUsage")
          end
        end

        context "when repository is nil" do
          test "does not self destruct when there are events" do
            @repository.update!(public: false)
            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            Timecop.freeze(1.hour.ago) do
              [
                create(
                  :shared_storage_artifact_event, :add_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 10
                ),
                create(
                  :shared_storage_artifact_event, :remove_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 2
                ),
                create(
                  :shared_storage_artifact_event, :unknown_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 3
                ),
              ]
            end

            @repository.destroy!
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_nothing_raised do
              current_usage.reload
            end

            hydro_payload = hydro_messages(schema: "meuse.v0.MeteredUsage").first

            assert_match /CurrentUsage/, hydro_payload[:source_uri]
          end

          test "self destructs when there are no events" do
            @repository.update!(public: false)
            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            @repository.destroy!
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_raises(ActiveRecord::RecordNotFound) do
              current_usage.reload
            end

            refute_hydro_messages(schema: "meuse.v0.MeteredUsage")
          end

          test "records metrics" do
            @repository.update!(public: false)
            stats = GitHub::MemoryDogstatsD.new
            GitHub.stubs(:dogstats).returns(stats)

            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            @repository.destroy!
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_equal 1, stats.increments("billing.shared_storage.aggregate_repositories_skipped", tags: ["reason:missing_repository"]).length
          end
        end

        context "when repository is not active" do
          test "does not self destruct when there are events" do
            @repository.update!(public: false)
            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            events = Timecop.freeze(1.hour.ago) do
              [
                create(
                  :shared_storage_artifact_event, :add_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 10
                ),
                create(
                  :shared_storage_artifact_event, :remove_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 2
                ),
                create(
                  :shared_storage_artifact_event, :unknown_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 3
                ),
              ]
            end

            @repository.remove(@repository.owner, synchronous: true)
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_nothing_raised do
              current_usage.reload
            end

            hydro_payload = hydro_messages(schema: "meuse.v0.MeteredUsage").first

            assert_match /CurrentUsage/, hydro_payload[:source_uri]
          end

          test "self destructs when there are no events" do
            @repository.update!(public: false)
            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            @repository.remove(@repository.owner, synchronous: true)
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_raises(ActiveRecord::RecordNotFound) do
              current_usage.reload
            end

            refute_hydro_messages(schema: "meuse.v0.MeteredUsage")
          end

          test "records metrics" do
            @repository.update!(public: false)
            stats = GitHub::MemoryDogstatsD.new
            GitHub.stubs(:dogstats).returns(stats)

            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end
            @repository.remove(@repository.owner, synchronous: true)
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_equal 1, stats.increments("billing.shared_storage.aggregate_repositories_skipped", tags: ["reason:inactive_repository"]).length
          end
        end

        context "when repository no longer belongs to the same owner" do
          test "does not self destruct when there are events" do
            @repository.update!(public: false)
            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            Timecop.freeze(1.hour.ago) do
              [
                create(
                  :shared_storage_artifact_event, :add_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 10
                ),
                create(
                  :shared_storage_artifact_event, :remove_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 2
                ),
                create(
                  :shared_storage_artifact_event, :unknown_event, :private_visibility,
                  repository: @repository,
                  size_in_bytes: 3
                ),
              ]
            end

            @repository.update!(owner: create(:user))
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_nothing_raised do
              current_usage.reload
            end

            hydro_payload = hydro_messages(schema: "meuse.v0.MeteredUsage").first

            assert_match /CurrentUsage/, hydro_payload[:source_uri]
          end

          test "self destructs when there are no events" do
            @repository.update!(public: false)
            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            @repository.update!(owner: create(:user))
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_raises(ActiveRecord::RecordNotFound) do
              current_usage.reload
            end

            refute_hydro_messages(schema: "meuse.v0.MeteredUsage")
          end

          test "records metrics" do
            stats = GitHub::MemoryDogstatsD.new
            GitHub.stubs(:dogstats).returns(stats)

            current_usage = Timecop.freeze(2.hours.ago) do
              create(
                :shared_storage_current_usage, :private_visibility,
                owner: @owner,
                repository: @repository,
                aggregate_size_in_bytes: 20
              )
            end

            @repository.update!(owner: create(:user))
            current_usage.reload

            current_usage.update_from_events_through!(cutoff: Time.current, start: 2.hours.ago.beginning_of_hour)
            assert_equal 1, stats.increments("billing.shared_storage.aggregate_repositories_skipped", tags: ["reason:owner_mismatch"]).length
          end
        end
      end
    end

    context "update_from_events!" do
      test "doesn't aggregate anything if it is already curent" do
        current_hour = Time.current.beginning_of_hour

        current_usage = create(
          :shared_storage_current_usage, :public_visibility,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 20,
          effective_at: current_hour
        )

        unaggregated_older_event = create(
          :shared_storage_artifact_event, :add_event, :public_visibility,
          repository: @repository,
          size_in_bytes: 10,
          effective_at: current_hour - 20.minutes
        )

        Timecop.freeze(current_hour + 20.minutes) do
          current_usage.update_from_events!
        end

        current_usage.reload
        unaggregated_older_event.reload

        assert_equal 20, current_usage.aggregate_size_in_bytes
        assert_equal current_hour, current_usage.effective_at
        assert_nil unaggregated_older_event.aggregation_id
      end

      test "aggregates events and emits to meuse for each hour on the hour between effective_at and the start of the current hour (and event window feature disabled)" do
        disable_feature_flag(:billing_large_event_windows)
        current_hour = Time.current.beginning_of_hour
        @repository.update!(public: false)

        most_recent_effective_at = current_hour - 3.hours

        current_usage = create(
          :shared_storage_current_usage, :private_visibility,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 100,
          effective_at: most_recent_effective_at
        )

        event1 = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repository,
          size_in_bytes: 100,
          effective_at: current_hour - 2.hours - 20.minutes
        )

        event2 = create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          repository: @repository,
          size_in_bytes: 50,
          effective_at: current_hour - 20.minutes
        )

        event3 = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repository,
          size_in_bytes: 10,
          effective_at: current_hour + 20.minutes
        )

        #We expect 3 aggregations
        # 1. now - 3hours -> now-2hours with an addion of 100 bytes (200 total) (event1)
        # 2. now - 2hours -> now-1hours with no additions (still 200 total)
        # 3. now - 1hours -> now with an removal of 50 bytes (150 total) (event2)
        # The future event should remain unaggregated

        Timecop.freeze(current_hour + 20.minutes) do
          current_usage.update_from_events!
        end

        assert_equal 3, hydro_messages(schema: "meuse.v0.MeteredUsage").length

        first_message = hydro_messages(schema: "meuse.v0.MeteredUsage").first
        second_message = hydro_messages(schema: "meuse.v0.MeteredUsage").second
        third_message = hydro_messages(schema: "meuse.v0.MeteredUsage").third

        [first_message, second_message, third_message].each do |message|
          assert_equal @repository.id.to_s, message.dig(:custom_fields, "repository.id")
          assert_match /CurrentUsage/, message[:source_uri]
        end

        assert_equal 200, first_message[:quantity]
        assert_equal 200, second_message[:quantity]
        assert_equal 150, third_message[:quantity]

        assert_equal current_hour, current_usage.effective_at

        [event1.reload, event2.reload].each do |event|
          assert_equal CurrentUsage::EVENT_AGGREGATION_ID, event.aggregation_id
        end

        assert_nil event3.reload.aggregation_id
      end

      test "aggregates events and emits to meuse for each hour on the hour between effective_at and the start of the current hour (and event window feature enabled)" do
        enable_feature_flag(:billing_large_event_windows)
        current_hour = Time.current.beginning_of_hour
        @repository.update!(public: false)
        window_size = Billing::SharedStorage::CurrentUsage::LARGE_EVENT_WINDOW_HOURS

        most_recent_effective_at = current_hour - (window_size + 1).hours

        current_usage = create(
          :shared_storage_current_usage, :private_visibility,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 100,
          effective_at: most_recent_effective_at
        )

        event1 = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repository,
          size_in_bytes: 100,
          effective_at: current_hour - (window_size).hours - 20.minutes
        )

        event2 = create(
          :shared_storage_artifact_event, :remove_event, :private_visibility,
          repository: @repository,
          size_in_bytes: 50,
          effective_at: current_hour - (window_size - 2).hours - 20.minutes
        )

        event3 = create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repository,
          size_in_bytes: 10,
          effective_at: current_hour + 20.minutes
        )

        Timecop.freeze(current_hour + 20.minutes) do
          current_usage.update_from_events!
        end

        assert_equal 1, hydro_messages(schema: "meuse.v0.MeteredUsage").length

        first_message = hydro_messages(schema: "meuse.v0.MeteredUsage").first

        assert_equal @repository.id.to_s, first_message.dig(:custom_fields, "repository.id")
        assert_match /CurrentUsage/, first_message[:source_uri]

        expected_quantity = 150 * window_size # 100 (original value) + 100 (event 1) - 50 (event 2) = 150
        assert_equal expected_quantity, first_message[:quantity]

        assert_equal most_recent_effective_at + (window_size).hours, current_usage.effective_at

        [event1.reload, event2.reload].each do |event|
          assert_equal CurrentUsage::EVENT_AGGREGATION_ID, event.aggregation_id
        end

        assert_nil event3.reload.aggregation_id
      end

      test "it handles self_destructs in hours before the curent hour" do
        disable_feature_flag(:billing_large_event_windows)
        current_hour = Time.current.beginning_of_hour
        @repository.update!(public: false)

        most_recent_effective_at = current_hour - 3.hours

        current_usage = create(
          :shared_storage_current_usage, :private_visibility,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 100,
          effective_at: most_recent_effective_at
        )

        create(
          :shared_storage_artifact_event, :add_event, :private_visibility,
          repository: @repository,
          size_in_bytes: 100,
          effective_at: current_hour - 2.hours - 20.minutes
        )

        @repository.destroy!

        Timecop.freeze(current_hour + 20.minutes) do
          current_usage.update_from_events!
        end

        hydro_payload = hydro_messages(schema: "meuse.v0.MeteredUsage").first

        assert_equal 200, hydro_payload[:quantity]
        assert_match /CurrentUsage/, hydro_payload[:source_uri]
        assert_equal @repository.id.to_s, hydro_payload.dig(:custom_fields, "repository.id")
      end

      test "it updates the effective_at to the current hour even if usage is 0 and there are no events" do
        disable_feature_flag(:billing_large_event_windows)
        current_hour = Time.current.beginning_of_hour
        @repository.update!(public: false)

        most_recent_effective_at = current_hour - 3.hours

        current_usage = create(
          :shared_storage_current_usage, :private_visibility,
          owner: @owner,
          repository: @repository,
          aggregate_size_in_bytes: 0,
          effective_at: most_recent_effective_at
        )

        Timecop.freeze(current_hour + 20.minutes) do
          current_usage.update_from_events!
        end

        assert_equal current_hour, current_usage.effective_at

        ArtifactEvent.expects(:where).never
        current_usage.update_from_events!
      end

      test "will process a max of 24 hours of events at a time" do
        Timecop.freeze(Time.new(2024, 3, 5, 8, 0, 0).utc) do
          current_hour = Time.current.beginning_of_hour

          most_recent_effective_at = current_hour - 25.hours

          current_usage = create(
            :shared_storage_current_usage, :private_visibility,
            owner: @owner,
            repository: @repository,
            aggregate_size_in_bytes: 0,
            effective_at: most_recent_effective_at
          )

          current_usage.update_from_events!
          assert_equal current_hour - 1.hour, current_usage.effective_at
        end
      end
    end
  end
end
