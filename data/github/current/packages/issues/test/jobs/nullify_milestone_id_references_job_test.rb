# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class NullifyMilestoneIdReferencesJobTest < GitHub::TestCase
  include JobTestHelper
  include HydroTestHelpers

  fixtures do
    @milestone = create :milestone
    @repo = @milestone.repository
    @user = @repo.owner

    @open_milestone_issues = 3.times.map { create(:issue, repository: @repo, milestone: @milestone) }
    @all_milestone_issues = (
      @open_milestone_issues +
      4.times.map { create(:issue, state: :closed, repository: @repo, milestone: @milestone) }
    )
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "does nothing if no issues exist for the given milestone" do
    assert_no_difference("IssueEvent.count") do
      assert_no_enqueued_jobs do
        NullifyMilestoneIdReferencesJob.perform_now(-1, "Non-existent milestone", nil, repository_id: @milestone.repository_id)
      end
    end
  end

  test "does nothing if the milestone has not been deleted" do
    assert_no_difference("IssueEvent.count") do
      assert_no_enqueued_jobs do
        NullifyMilestoneIdReferencesJob.perform_now(@milestone.id, @milestone.title, @user.id, repository_id: @milestone.repository_id)
      end
    end

    assert_equal 1, GitHub.dogstats.increments("job.nullify_milestone_id_references.milestone_still_exists").length
  end

  test "creates demilestoned events and nullifies milestone_id references" do
    @milestone.delete

    assert_difference("IssueEvent.demilestones.count", 3) do
      NullifyMilestoneIdReferencesJob.perform_now(@milestone.id, @milestone.title, @user.id, repository_id: @milestone.repository_id)
    end

    @all_milestone_issues.each(&:reload)
    assert @open_milestone_issues.all? { |i| i.events.last.event == "demilestoned" }
    assert @all_milestone_issues.all? { |i| i.milestone_id.nil? }
  end

  test "can skip creating demilestoned events while still nullifying milestone_id references" do
    @milestone.delete

    assert_no_difference("IssueEvent.demilestones.count") do
      NullifyMilestoneIdReferencesJob.perform_now(@milestone.id, @milestone.title, @user.id, create_demilestoned_events: false, repository_id: @milestone.repository_id)
    end

    @all_milestone_issues.each(&:reload)
    assert @all_milestone_issues.all? { |i| i.milestone_id.nil? }
  end

  test "does nothing if the repo was deleted" do
    @repo.destroy
    @milestone.delete

    assert_no_difference("IssueEvent.count") do
      assert_no_enqueued_jobs do
        NullifyMilestoneIdReferencesJob.perform_now(@milestone.id, @milestone.title, @user.id, repository_id: @milestone.repository_id)
      end
    end
  end

  test "completes its work even if it needs to process several batches" do
    @milestone.delete

    NullifyMilestoneIdReferencesJob.stub_const(:BATCH_SIZE, 2) do
      assert_difference("IssueEvent.demilestones.count", 3) do
        assert_performed_jobs(3, only: NullifyMilestoneIdReferencesJob) do
          NullifyMilestoneIdReferencesJob.perform_now(@milestone.id, @milestone.title, @user.id, repository_id: @milestone.repository_id)
        end
      end
    end

    @all_milestone_issues.each(&:reload)
    assert @open_milestone_issues.all? { |i| i.events.last.event == "demilestoned" }
    assert @all_milestone_issues.all? { |i| i.milestone_id.nil? }
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: NullifyMilestoneIdReferencesJob, args: [@milestone.id, @milestone.title, @user.id, @milestone.repository_id]
  end

  unless GitHub.enterprise?
    context "Hydro Instrumentation" do
      test "does not publish issue update milestone events to hydro when the milestone itself is deleted and processed by the NullifyMilestoneIdReferencesJob" do
        GitHub.context.push(actor_id: @user.id)
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        milestone = create :milestone, repository: repo, title: "Beta Release 0.5"
        open_milestone_issues = 3.times.map { create(:issue, repository: repo, milestone: milestone) }
        reset_hydro

        assert_performed_with job: NullifyMilestoneIdReferencesJob do
          milestone.destroy
        end

        refute_hydro_messages(schema: "github.v1.IssueUpdateMilestone")
      end
    end
  end
end
