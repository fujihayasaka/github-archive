# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::TransitionInactiveSecurityUpdateReposToPaused, type: :job, feature: :inactivity_pausing do
  subject(:job) { described_class.new }

  describe "#perform" do
    it "pauses repos with automated security updates enabled and security update configs" do
      create(:repo, :security_updates_only, :automated_security_updates, will_pause_at: 1.day.ago)

      expect { job.perform_now }.to enqueue_job(PauseRepoJob)
    end

    it "does not pause repos with version update configs" do
      create(:repo, :active, will_pause_at: 1.day.ago)

      expect { job.perform_now }.not_to enqueue_job(PauseRepoJob)
    end

    it "does not pause repos with automated security updates disabled" do
      create(:repo, :security_updates_only, :manual_security_updates, will_pause_at: 1.day.ago)

      expect { job.perform_now }.not_to enqueue_job(PauseRepoJob)
    end

    it "does not pause inactive repos" do
      create(:repo, :inactive, will_pause_at: 1.day.ago)

      expect { job.perform_now }.not_to enqueue_job(PauseRepoJob)
    end

    it "does not re-pause or un-pause repos that are already paused" do
      create(
        :repo,
        :security_updates_only,
        :automated_security_updates,
        paused_at: 1.day.ago,
        will_pause_at: 1.day.ago,
      )

      expect { job.perform_now }.not_to enqueue_job(PauseRepoJob)
    end

    it "does not pause repos that are not scheduled to be paused" do
      create(:repo, :security_updates_only, :automated_security_updates, will_pause_at: 1.day.from_now)

      job.perform_now

      expect { job.perform_now }.not_to enqueue_job(PauseRepoJob)
    end

    context "when a repository has multiple configs" do
      let(:repo) do
        create(:repo, :security_updates_only, :automated_security_updates, will_pause_at: 1.day.ago)
      end

      before do
        repo.update_configs.active.
          create_with(update_schedule: "never").
          find_or_create_by!(
            package_manager: "npm_and_yarn",
            directory: "/",
            lockfile_only: false,
            default_labels: ["dependencies"],
            allowed_updates: [
              { "dependency_type" => "direct", "update_type" => "all" },
              { "dependency_type" => "indirect", "update_type" => "security" },
            ],
            update_schedule_time_of_day: "05:00",
            update_schedule_day_of_week: "monday",
            update_schedule_timezone: "UTC",
            pull_request_branch_name_separator: "/",
            open_pull_requests_limit: UpdateConfig::DEFAULT_OPEN_PULL_REQUESTS_LIMIT,
            rebase_strategy: "auto"
          ).transition_to!(:rate_limited)
      end

      it "does not attempt to pause a repository with mutiple configs more than once" do
        expect { job.perform_now }.to enqueue_job(PauseRepoJob).with(repo_id: repo.id, event_source: anything).once
      end
    end
  end
end
