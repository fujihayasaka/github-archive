# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProject
  class VisitedAfterReconcilerTest < GitHub::TestCase
    include GitHub::LoggerHelper

    fixtures do
      @reconciled_user = create(:user)
    end

    def create_reconciler(opts = {})
      MemexProject::VisitedAfterReconciler.new({
        index: opts.fetch(:index, Elastomer::Indexes::MemexProjectItems.new),
        group_key: "reconciler-test",
        reconcile_id: SecureRandom.hex,
        attempt: 1,
        visited_after: 1.week.ago.to_date,
      }.merge(opts))
    end

    setup do
      Failbot.reports.clear
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @index = Elastomer::Indexes::MemexProjectItems.new
      @document_type = Elastomer::Adapters::MemexProjectItem.document_type
      @cluster = Elastomer.router.cluster_for_index(@index.name)
      @reconciler = create_reconciler(index: @index).tap(&:reset!)
      @organization = create(:organization)
      @user = create(:verified_user).tap { |user| @organization.add_member(user) }
      @memex_project_without_limits = create(:memex_project, owner: @organization, creator: @user)
      @another_memex_project_without_limits = create(:memex_project, owner: @organization, creator: @user)
      @memex_legacy_project = create(:memex_project, owner: @organization, creator: @user)

      setup_search

      GitHub.flipper[:memex_table_without_limits].enable(@memex_project_without_limits)
      GitHub.flipper[:memex_table_without_limits].enable(@another_memex_project_without_limits)
      GitHub.flipper[:memex_increased_issues_graph_timeouts].disable
    end

    test "default to raising errors to allow for bubbling up exceptions necessary for retries" do
      assert_equal true, @reconciler.raise_errors
    end

    test "projects are iterated on in reasonable batch size" do
      assert_equal MemexProjectItems::Reconciler::MEMEX_PROJECT_BATCH_SIZE, @reconciler.limit
    end

    context "#last_id" do
      test "returns default 0 if no MemexProjectVisits" do
        assert_equal 0, MemexProjectVisit.count, "Expected no MemexProjectVisits"
        assert_equal 0, @reconciler.last_id, "Expected no last_id"
      end

      test "returns last MemexProject that will be reconciled" do
        reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01")).tap(&:reset!)

        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-02"))
        @another_memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-03"))
        @memex_legacy_project.update!(last_visited_on: Date.iso8601("2024-06-04"))

        assert_equal @memex_legacy_project.id, reconciler.last_id, "Expected last_id to be the last MemexProject visited"
      end

      test "limits projects to reconcile based on when they were last visited" do
        reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-04")).tap(&:reset!)

        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-01"))
        @another_memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-02"))
        @memex_legacy_project.update!(last_visited_on: Date.iso8601("2024-06-03"))

        assert_equal 0, reconciler.last_id, "Expected last_id to not return MemexProject visited after 1 day ago"
      end
    end

    context "#progress" do
      test "returns default 0.0 if no MemexProjectVisits" do
        assert_equal 0, MemexProjectVisit.count, "Expected no MemexProjectVisits"
        assert_equal 0.0, @reconciler.progress, "Expected no progress"
      end

      test "keeps track of progress throughout batches" do
        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-08"))

        reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01"), limit: 1).tap(&:reset!)
        assert_changes -> { reconciler.progress }, from: 0.0, to: 100.0 do
          reconciler.reconcile
        end
      end
    end

    context "#last_memex_project_id" do
      test "returns default project offset" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        assert_equal 0, reconciler.last_memex_project_id
      end

      test "retrieves stored project offset" do
        reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01")).tap(&:reset!)

        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-08"))

        reconciler.reconcile

        assert_equal @memex_project_without_limits.id, reconciler.last_memex_project_id
      end
    end

    context "#last_visited_on" do
      test "returns default date" do
        visited_after = Date.iso8601("2024-06-01")
        reconciler = create_reconciler(index: @index, visited_after:).tap(&:reset!)

        assert_equal visited_after, reconciler.last_visited_on
      end

      test "retrieves stored date" do
        reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01")).tap(&:reset!)
        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-08"))

        reconciler.reconcile

        assert_equal @memex_project_without_limits.last_visited_on, reconciler.last_visited_on
      end
    end

    context "#get_offset" do
      test "returns default offset" do
        visited_after = Date.iso8601("2024-06-01")
        reconciler = create_reconciler(index: @index, visited_after:).tap(&:reset!)
        expected_cursor = [visited_after, 0]

        assert_equal expected_cursor, reconciler.get_offset
      end

      test "retrieves stored offset" do
        freeze_time

        reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01")).tap(&:reset!)
        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-08"))
        expected_cursor = [Date.iso8601("2024-06-08"), @memex_project_without_limits.id]

        reconciler.reconcile

        assert_equal expected_cursor, reconciler.get_offset
      end
    end

    context "#reconciler_memex_project_ids" do
      test "does not return any project ids if there are no visits" do
        reconciler = create_reconciler(index: @index).tap(&:reset!)

        assert_equal 0, MemexProjectVisit.count, "Expected no MemexProjectVisits"
        assert_empty reconciler.reconciler_memex_project_ids, "Expected no MemexProject ids"
      end

      test "returns first page of projects since last reconciled project" do
        freeze_time

        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-07"))
        @another_memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-08"))
        first_batch_reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01"), limit: 1).tap(&:reset!)

        assert_equal [@memex_project_without_limits.id], first_batch_reconciler.reconciler_memex_project_ids

        second_batch_reconciler = create_reconciler(index: @index, limit: 1)
        assert_equal [@another_memex_project_without_limits.id], second_batch_reconciler.reconciler_memex_project_ids
      end

      test "returns empty page of projects when maximum last_visited_on is reached" do
        freeze_time

        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-07"))
        first_batch_reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01"), limit: 1).tap(&:reset!)

        assert_equal [@memex_project_without_limits.id], first_batch_reconciler.reconciler_memex_project_ids

        second_batch_reconciler = create_reconciler(index: @index, limit: 1)
        assert_empty second_batch_reconciler.reconciler_memex_project_ids
      end

      test "does not skip project with same date" do
        travel_to Date.iso8601("2024-01-01")

        opts = {
          index: @index,
          visited_after: Date.iso8601("2023-12-31"),
          limit: 1,
        }

        # Purposefully out of order, to test that the last visit is used for each group
        dup_last_visited_on = "2024-01-01"
        @memex_project_without_limits.update!(last_visited_on: Date.iso8601(dup_last_visited_on))
        @another_memex_project_without_limits.update!(last_visited_on: Date.iso8601(dup_last_visited_on))
        @memex_legacy_project.update!(last_visited_on: Date.iso8601("2024-01-02"))
        first_batch_reconciler = create_reconciler(opts).tap(&:reset!)

        assert @another_memex_project_without_limits.id > @memex_project_without_limits.id, "Expected another_memex_project_without_limits to have been created after memex_project_without_limits"
        assert_equal dup_last_visited_on, @memex_project_without_limits.last_visited_on.iso8601, "Expected first_memex_project_visit to have last_visited_on of #{dup_last_visited_on}"
        assert_equal dup_last_visited_on, @another_memex_project_without_limits.last_visited_on.iso8601, "Expected first_memex_project_visit to have last_visited_on of #{dup_last_visited_on}"
        assert_equal [@memex_project_without_limits.id], first_batch_reconciler.reconciler_memex_project_ids

        second_batch_reconciler = create_reconciler(opts)
        assert_equal [@another_memex_project_without_limits.id], second_batch_reconciler.reconciler_memex_project_ids

        third_batch_reconciler = create_reconciler(opts)
        assert_equal [@memex_legacy_project.id], third_batch_reconciler.reconciler_memex_project_ids
      end
    end

    context "#reconcile" do
      test "repairs all projects with a visit after the visited_after date" do
        reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01")).tap(&:reset!)
        @memex_legacy_project.update!(last_visited_on: Date.iso8601("2023-01-01"))
        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-05-01"))
        @another_memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-08"))
        another_memex_project_without_limits_items = create_list(:memex_project_item, 5, memex_project: @another_memex_project_without_limits)
        another_memex_project_without_limits_document_count = lambda do
          @index.count_all({
            query: {
              term: {
                memex_project_id: @another_memex_project_without_limits.id,
              }
            }
          })
        end

        assert_changes another_memex_project_without_limits_document_count, from: 0, to: 5 do
          assert_changes -> { reconciler.memex_projects_reconciled_count }, from: 0, to: 1 do
            assert_changes -> { reconciler.last_memex_project_id }, from: 0, to: @another_memex_project_without_limits.id do
              reconciler.reconcile

              Elastomer::TestHelpers.index_refresh(@index.name)
            end
          end
        end
      end

      test "does not repair project not in memex_table_without_limits feature flag" do
        reconciler = create_reconciler(index: @index, visited_after: Date.iso8601("2024-06-01")).tap(&:reset!)
        @memex_project_without_limits.update!(last_visited_on: Date.iso8601("2024-06-05"))
        @memex_legacy_project.update!(last_visited_on: Date.iso8601("2024-06-07"))
        create_list(:memex_project_item, 5, memex_project: @memex_project_without_limits)
        create_list(:memex_project_item, 5, memex_project: @memex_legacy_project)
        memex_legacy_project_document_count = lambda do
          @index.count_all({
            query: {
              term: {
                memex_project_id: @memex_legacy_project.id,
              }
            }
          })
        end
        memex_project_without_limits_document_count = lambda do
          @index.count_all({
            query: {
              term: {
                memex_project_id: @memex_project_without_limits.id,
              }
            }
          })
        end

        refute @memex_legacy_project.feature_enabled?(:memex_table_without_limits), "Expected memex_legacy_project to not have memex_table_without_limits feature flag enabled"
        assert_no_changes memex_legacy_project_document_count, from: 0 do
          assert_changes memex_project_without_limits_document_count, from: 0, to: 5 do
            assert_changes -> { reconciler.memex_projects_reconciled_count }, from: 0, to: 1 do
              assert_changes -> { reconciler.last_memex_project_id }, from: 0, to: @memex_legacy_project.id do
                assert_changes -> { reconciler.reconciled_memex_project_ids.to_a.sort }, from: [], to: [@memex_project_without_limits.id, @memex_legacy_project.id] do
                  reconciler.reconcile

                  Elastomer::TestHelpers.index_refresh(@index.name)
                end
              end
            end
          end
        end
      end
    end
  end
end
