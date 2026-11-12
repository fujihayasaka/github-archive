# frozen_string_literal: true

require "rails_helper"

RSpec.describe Activity::PauseManager do
  let(:activity_manager) do
    described_class.new(repo: repo)
  end

  before do
    allow(Dependabot::Logger).to receive(:info)
    allow(Dependabot::Logger).to receive(:log_context).and_call_original
  end

  describe "#watch_for_inactivity!", feature: :inactivity_pausing do
    subject(:watch_for_inactivity!) do
      activity_manager.watch_for_inactivity!("pull-request.create")
    end

    context "with an active repo" do
      let(:repo) { FactoryBot.create(:repo, :no_pause_planned) }

      it "sets a pause date in the future" do
        expect { watch_for_inactivity! }.
          to change(repo, :will_pause_at).
          from(nil).to(within(1.second).of(90.days.from_now.utc))
      end

      it "logs the event" do
        watch_for_inactivity!

        expect(Dependabot::Logger).to have_received(:log_context).
          with(hash_including(context: "repository-activity-monitor"))

        expect(Dependabot::Logger).to have_received(:info).with(
          {
            activity_log_event: "repository-activity-monitor.watched-for-inactivity",
            triggered_by: "pull-request.create",
          }
        )
      end

      it "permits setting of immediate pauses for testing" do
        repo.enable_feature(:dependabot_paused_test_immediate)

        expect { watch_for_inactivity! }.
          to change(repo, :will_pause_at).
          from(nil).to(within(1.second).of(Time.now.utc))
      end

      it "permits setting of 24 hour pauses for testing" do
        repo.enable_feature(:dependabot_paused_test_24_hours)

        expect { watch_for_inactivity! }.
          to change(repo, :will_pause_at).
          from(nil).to(within(1.second).of(24.hours.from_now.utc))
      end
    end

    context "with a repository already monitored for inactivity" do
      let(:repo) { FactoryBot.create(:repo, :will_pause_later) }

      it "does not change the existing planned pause timestamp" do
        expect { watch_for_inactivity! }.not_to change(repo, :will_pause_at)
      end

      it "doesn't log anything" do
        watch_for_inactivity!

        expect(Dependabot::Logger).not_to have_received(:log_context).
          with(hash_including(context: "repository-activity-monitor"))
      end
    end

    context "with a repository that has already been paused" do
      let(:repo) { FactoryBot.create(:repo, :currently_paused) }

      it "does not change the existing planned pause timestamp" do
        expect { watch_for_inactivity! }.not_to change(repo, :will_pause_at)
      end

      it "does not change the actual pause timestamp" do
        expect { watch_for_inactivity! }.not_to change(repo, :paused_at)
      end

      it "logs that we skipped an attempt to re-watch the repository" do
        watch_for_inactivity!

        expect(Dependabot::Logger).to have_received(:log_context).
          with(hash_including(context: "repository-activity-monitor"))

        expect(Dependabot::Logger).to have_received(:info).with(
          {
            activity_log_event: "repository-activity-monitor.watched-for-inactivity.already-paused",
            triggered_by: "pull-request.create",
          }
        )
      end
    end
  end

  describe "#mark_as_active!", feature: :inactivity_pausing do
    subject(:mark_as_active!) do
      activity_manager.mark_as_active!("pull-request.merged")
    end

    context "with an active repo" do
      let(:repo) { FactoryBot.create(:repo, :no_pause_planned) }

      it "is a noop" do
        # Verify we don't touch the db record
        expect { mark_as_active! }.not_to change(repo, :updated_at)
      end

      it "doesn't log anything" do
        mark_as_active!

        expect(Dependabot::Logger).not_to have_received(:log_context).
          with(hash_including(context: "repository-activity-monitor"))
      end

      it "doesn't trigger any jobs" do
        expect { mark_as_active! }.not_to have_enqueued_job
      end
    end

    context "with a repository monitored for inactivity" do
      let(:repo) { FactoryBot.create(:repo, :will_pause_later) }

      it "removes the planned pause timestamp" do
        expect { mark_as_active! }.to change(repo, :will_pause_at).to(nil)
      end

      it "logs the event" do
        mark_as_active!

        expect(Dependabot::Logger).to have_received(:log_context).
          with(hash_including(context: "repository-activity-monitor"))

        expect(Dependabot::Logger).to have_received(:info).with(
          {
            activity_log_event: "repository-activity-monitor.marked-as-active",
            triggered_by: "pull-request.merged",
            unpaused: false,
          }
        )
      end

      it "doesn't trigger any jobs" do
        expect { mark_as_active! }.not_to have_enqueued_job
      end
    end

    context "with a repository that has already been paused" do
      let(:repo) { FactoryBot.create(:repo, :currently_paused) }

      it "removes the planned pause timestamp" do
        expect { mark_as_active! }.to change(repo, :will_pause_at).to(nil)
      end

      it "removes the pause" do
        expect { mark_as_active! }.to change(repo, :paused_at).to(nil)
      end

      it "logs the event" do
        mark_as_active!

        expect(Dependabot::Logger).to have_received(:log_context).
          with(hash_including(context: "repository-activity-monitor"))

        expect(Dependabot::Logger).to have_received(:info).with(
          {
            activity_log_event: "repository-activity-monitor.marked-as-active",
            triggered_by: "pull-request.merged",
            unpaused: true,
          }
        )
      end

      it "enqueues a job to resync after being paused" do
        expect { mark_as_active! }.to have_enqueued_job(ResyncUnpausedRepoJob)
      end
    end
  end
end
