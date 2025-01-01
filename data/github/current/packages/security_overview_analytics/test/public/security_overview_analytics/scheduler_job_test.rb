# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class SchedulerJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    context "#CalendarPopulationJob" do
      test "is scheduled once within a day" do
        now = Time.utc(2024, 06, 01)
        Timecop.freeze now do
          assert_enqueued_jobs 1, only: CalendarPopulationJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end

        later = now + 23.hours
        Timecop.freeze later do
          assert_enqueued_jobs 0, only: CalendarPopulationJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end
      end

      test "can be scheduled again past 1 day window" do
        now = Time.utc(2024, 06, 01)
        Timecop.freeze now do
          assert_enqueued_jobs 1, only: CalendarPopulationJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end

        later = now + 25.hours
        Timecop.freeze later do
          assert_enqueued_jobs 1, only: CalendarPopulationJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end
      end
    end

    context "#RepositoryDataCleanupJob" do
      test "is scheduled once within a week" do
        now = Time.utc(2024, 06, 01)
        Timecop.freeze now do
          assert_enqueued_jobs 1, only: RepositoryDataCleanupJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end

        later = now + 6.days
        Timecop.freeze later do
          assert_enqueued_jobs 0, only: RepositoryDataCleanupJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end
      end

      test "can be scheduled again past 1 week window" do
        now = Time.utc(2024, 06, 01)
        Timecop.freeze now do
          assert_enqueued_jobs 1, only: RepositoryDataCleanupJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end

        later = now + 8.days
        Timecop.freeze later do
          assert_enqueued_jobs 1, only: RepositoryDataCleanupJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end
      end
    end

    context "#DataRetentionEnforcementJob" do
      test "is scheduled once within a week" do
        now = Time.utc(2024, 06, 01)
        Timecop.freeze now do
          assert_enqueued_jobs 1, only: DataRetentionEnforcementJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end

        later = now + 6.days
        Timecop.freeze later do
          assert_enqueued_jobs 0, only: DataRetentionEnforcementJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end
      end

      test "can be scheduled again past 1 week window" do
        now = Time.utc(2024, 06, 01)
        Timecop.freeze now do
          assert_enqueued_jobs 1, only: DataRetentionEnforcementJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end

        later = now + 8.days
        Timecop.freeze later do
          assert_enqueued_jobs 1, only: DataRetentionEnforcementJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end
      end
    end

    context "#RepositoryDataCompressionJob" do
      test "is scheduled once within 60 days" do
        now = Time.utc(2024, 06, 01)
        Timecop.freeze now do
          assert_enqueued_jobs 1, only: RepositoryDataCompressionJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end

        later = now + 59.days
        Timecop.freeze later do
          assert_enqueued_jobs 0, only: RepositoryDataCompressionJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end
      end

      test "can be scheduled again past 60 days window" do
        now = Time.utc(2024, 06, 01)
        Timecop.freeze now do
          assert_enqueued_jobs 1, only: RepositoryDataCompressionJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end

        later = now + 61.days
        Timecop.freeze later do
          assert_enqueued_jobs 1, only: RepositoryDataCompressionJob do
            perform_enqueued_jobs only: SchedulerJob do
              SchedulerJob.perform_later
            end
          end
        end
      end
    end
  end
end
