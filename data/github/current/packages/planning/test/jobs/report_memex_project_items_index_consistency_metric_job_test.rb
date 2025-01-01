# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ReportMemexProjectItemsIndexConsistencyMetricJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @frozen_date = Time.new(2024, 8, 14, 0, 10, 0).utc.freeze
    @projects = create_list(:memex_project, 2, last_visited_on: @frozen_date)
  end

  context "#perform" do
    test "computes a consistency metric from the results of previous consistency evaluations" do
      setup_consistency(
        @projects[0] => { consistency: 0.9, evaluated_at: @frozen_date },
        @projects[1] => { consistency: 1.0, evaluated_at: @frozen_date }
      )

      perform_enqueued_resync_job

      assert_dogstats_gauge_value(50, ReportMemexProjectItemsIndexConsistencyMetricJob::CONSISTENCY_METRIC_NAME)
      assert_dogstats_gauge_value(2, ReportMemexProjectItemsIndexConsistencyMetricJob::SAMPLE_SIZE_METRIC_NAME)
    end

    test "computes a consistency metric respecting a sample size of previous consistency evaluations" do
      sample_size = 0.5
      projects = create_list(:memex_project, 10, last_visited_on: @frozen_date)

      # all projects start inconsistent
      0.1.step(0.9, 0.1).each_with_index do |consistency, index|
        setup_consistency(projects[index] => { consistency: consistency, evaluated_at: Time.new.utc })
      end

      # only one project will be considered consistent given the sample size of 50% of all projects
      # this is because the other consistent project `evaluated_at` timestamp is older than the only other consistent project
      # therefore, only considering the most recent evaluation for each project within the considered sample size
      setup_consistency(
        projects[0] => { consistency: 1.0, evaluated_at: Time.new.utc },
        projects[9] => { consistency: 1.0, evaluated_at: Time.new(1999, 8, 14, 0, 10, 0).utc },
      )

      # consider a sample of 50% of the projects
      perform_enqueued_resync_job(subset: sample_size)

      assert_dogstats_gauge_value(20, ReportMemexProjectItemsIndexConsistencyMetricJob::CONSISTENCY_METRIC_NAME)
      assert_dogstats_gauge_value(5, ReportMemexProjectItemsIndexConsistencyMetricJob::SAMPLE_SIZE_METRIC_NAME)
    end

    test "tags consistency metric appropriately when resync jobs do not all succeed" do
      setup_consistency(
        @projects[0] => {},
        @projects[1] => { consistency: 1.0, evaluated_at: @frozen_date },
      )

      perform_enqueued_resync_job

      assert_dogstats_gauge_value(50, ReportMemexProjectItemsIndexConsistencyMetricJob::CONSISTENCY_METRIC_NAME)
      assert_dogstats_gauge_value(2, ReportMemexProjectItemsIndexConsistencyMetricJob::SAMPLE_SIZE_METRIC_NAME)
    end

    test "tags consistency metric with the oldest evaluation date" do
      now = Time.now.utc
      one_week_ago = now - 1.week

      setup_consistency(
        @projects[0] => { consistency: 0.9, evaluated_at: now },
        @projects[1] => { consistency: 1.0, evaluated_at: one_week_ago },
      )

      perform_enqueued_resync_job

      assert_dogstats_gauge_value(
        one_week_ago.to_i,
        ReportMemexProjectItemsIndexConsistencyMetricJob::OLDEST_EVALUATION_METRIC_NAME
      )
    end

    test "does not report consistency metric when we can't compute a meaningful value for it" do
      # We do not setup any consistency evaluations for this test, so the job will not be able to compute a meaningful
      # value for the overal consistency metric.
      expected_log_attributes = {
        "Body" => "Could not compute meaningful value for consistency metric because total number of projects considered was zero",
        "code.namespace" => "ReportMemexProjectItemsIndexConsistencyMetricJob",
        "code.function" => "perform",
      }

      assert_logged(**expected_log_attributes) do
        perform_enqueued_jobs only: [ReportMemexProjectItemsIndexConsistencyMetricJob] do
          ReportMemexProjectItemsIndexConsistencyMetricJob.perform_now
        end
      end

      refute_dogstats_stat(:gauge, ReportMemexProjectItemsIndexConsistencyMetricJob::CONSISTENCY_METRIC_NAME)
    end

    test "does not raise exception when project cannot be found" do
      MemexProject.stubs(:memex_without_limits_beta_projects).returns([@projects.map(&:id), -1].flatten)

      perform_enqueued_resync_job
    end

    test "only allows a single instance of the job at any one time" do
      assert_enqueued_jobs 1 do
        ReportMemexProjectItemsIndexConsistencyMetricJob.perform_later
        ReportMemexProjectItemsIndexConsistencyMetricJob.perform_later
      end
    end
  end

  private def perform_enqueued_resync_job(subset: 1)
    MemexProjectElasticsearchConsistency.stub_const(:SAMPLE_PERCENTAGE, subset) do
      perform_enqueued_jobs only: [ReportMemexProjectItemsIndexConsistencyMetricJob] do
        ReportMemexProjectItemsIndexConsistencyMetricJob.perform_now
      end
    end
  end

  sig { params(expectations: T::Hash[MemexProject, { consistency: Float, evaluated_at: T.nilable(Time) }]).void }
  private def setup_consistency(expectations)
    expectations.each do |project, args|
      MemexProjectElasticsearchConsistency
        .find_or_initialize_by(memex_project_id: T.must(project.id))
        .update!(args)
    end
  end
end
