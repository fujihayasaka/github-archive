# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::EnqueueScheduledUpdates, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class }

  let(:account) do
    FactoryBot.create(
      :account, :active,
    )
  end

  let(:repo) { FactoryBot.create(:repo, account: account) }

  context "when the run_timed_enqueue_scheduled_updates_job FF is enabled" do
    let(:now) { Time.now.utc }
    let(:perform_job) { job.perform_now("weekly", now: now) }

    before do
      stub_monolith_feature(:run_timed_enqueue_scheduled_updates_job, actor: nil)
    end

    it "proxies to the new timed job" do
      expect { perform_job }.
        to have_enqueued_job(ScheduledJobs::EnqueueScheduledUpdatesTimed).
        with(schedule_type: "weekly", initial_start: now)
    end

    it "does not enqueue any update jobs" do
      expect { perform_job }.not_to have_enqueued_job(CreateScheduledUpdateJob)
      expect(MetricsClient).not_to receive(:time).
        with("enqueue_scheduled_updates_job.weekly.time")
    end
  end

  # rubocop:disable RSpec/AnyInstance
  describe "filtering jobs by schedule type and state" do
    setup do
      allow_any_instance_of(ScheduledJobs::EnqueueScheduledUpdates::IntervalVerification).to receive(:matches_config?).
        and_return(true)
    end

    it "defaults to running weekly" do
      expect(MetricsClient).to receive(:time).
        with("enqueue_scheduled_updates_job.weekly.time")

      job.perform_now
    end

    it "rejects unknown schedules" do
      expect { job.perform_now("garbage") }.
        to raise_error(ArgumentError), "Invalid schedule: 'garbage'"
    end

    it "accepts cron schedule" do
      expect { job.perform_now("cron") }.
        not_to raise_error
    end

    it "accepts quarter schedule" do
      expect { job.perform_now("quarterly") }.
        not_to raise_error
    end

    it "accepts semiannually schedule" do
      expect { job.perform_now("semiannually") }.
        not_to raise_error
    end

    it "accepts yearly schedule" do
      expect { job.perform_now("yearly") }.
        not_to raise_error
    end

    context "with a schedule of daily" do
      let(:perform_job) { job.perform_now("daily") }

      it "instruments the scheduled job" do
        expect(MetricsClient).to receive(:time).
          with("enqueue_scheduled_updates_job.daily.time")

        perform_job
      end

      context "daily configs that are deleted" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :deleted,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.daily", 0)

          perform_job
        end
      end

      context "daily configs that are active with active installations" do
        let(:update_schedule_time_of_day) { Time.zone.now }

        let!(:update_config) do
          update_schedule_time_of_day.change({ min: rand(59) })
          FactoryBot.create(
            :update_config,
            :active,
            repo: repo,
            update_schedule_time_of_day: update_schedule_time_of_day,
          )
        end

        it "enqueues an update job with no wait" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob).at(:no_wait)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.daily", 1)

          perform_job
        end

        context "when updates are spread out randomly" do
          before do
            account.enable_feature(:spread_out_updates)
            allow(Time).to receive(:now).and_return(update_schedule_time_of_day)
          end

          it "enqueues an update job" do
            expect { perform_job }.
              to have_enqueued_job(CreateScheduledUpdateJob).at(
                a_value_within(60.minutes).of(Time.zone.now)
              )
          end

          it "didn't enqueue it with no wait" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob).at(:no_wait)
          end
        end

        context "when updates are spread out using the user configured value" do
          before do
            account.enable_feature(:spread_out_updates_time_of_day)
          end

          it "enqueues an update job" do
            expect { perform_job }.
              to have_enqueued_job(CreateScheduledUpdateJob).at(
                a_value_within(2.minutes).of(update_schedule_time_of_day)
              )
          end

          it "didn't enqueue it with no wait" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob).at(:no_wait)
          end
        end

        context "when the repo is paused", feature: :inactivity_pausing do
          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "doesn't enqueue a create scheduled update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end

          it "instruments active, unpaused update configs" do
            expect(MetricsClient).to receive(:gauge).
              with("scheduled_update_configs.daily", 0)

            perform_job
          end
        end
      end

      context "active weekly configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :weekly,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "active monthly configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :monthly,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end
    end

    context "with schedule of weekly" do
      let(:perform_job) { job.perform_now("weekly") }

      it "instruments the scheduled job" do
        expect(MetricsClient).to receive(:time).
          with("enqueue_scheduled_updates_job.weekly.time")

        perform_job
      end

      context "active daily configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :daily,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "weekly configs that are deleted" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :deleted,
            :weekly,
            repo: repo,
          )
        end

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.weekly", 0)

          perform_job
        end
      end

      context "weekly configs that are active with active installations" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :weekly,
            repo: repo,
          )
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.weekly", 1)

          perform_job
        end

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "when the repo is paused", feature: :inactivity_pausing do
          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "doesn't enqueue a create scheduled update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end

      context "active monthly configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :monthly,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end
    end

    context "with schedule of monthly" do
      let(:perform_job) { job.perform_now("monthly") }

      it "instruments the scheduled job" do
        expect(MetricsClient).to receive(:time).
          with("enqueue_scheduled_updates_job.monthly.time")

        perform_job
      end

      context "active daily configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :daily,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "active weekly configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :weekly,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "monthly configs that are deleted" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :deleted,
            :monthly,
            repo: repo,
          )
        end

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.monthly", 0)

          perform_job
        end
      end

      context "monthly configs that are active with active installations" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :monthly,
            repo: repo,
          )
        end

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.monthly", 1)

          perform_job
        end

        context "when the repo is paused", feature: :inactivity_pausing do
          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "doesn't enqueue a create scheduled update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end
    end

    context "with cron schedule" do
      let(:perform_job) { job.perform_now("cron") }

      it "instruments the scheduled job" do
        expect(MetricsClient).to receive(:time).
          with("enqueue_scheduled_updates_job.cron.time")

        perform_job
      end

      context "active daily configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :daily,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "active weekly configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :weekly,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron configs that are deleted" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :deleted,
            :cron,
            repo: repo,
          )
        end

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.cron", 0)

          perform_job
        end
      end

      context "cron configs that are active with active installations" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 3) }
        let(:cron_expression) { "0 3 * * *" }

        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :cron,
            repo: repo,
            update_schedule_cron_expression: cron_expression,
          )
        end

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.cron", 1)

          perform_job
        end

        context "when the repo is paused", feature: :inactivity_pausing do
          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "doesn't enqueue a create scheduled update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end
    end

    context "with quarterly schedule" do
      let(:perform_job) { job.perform_now("quarterly") }

      it "instruments the scheduled job" do
        expect(MetricsClient).to receive(:time).
          with("enqueue_scheduled_updates_job.quarterly.time")

        perform_job
      end

      context "active daily configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :daily,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "active weekly configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :weekly,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "quarterly configs that are deleted" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :deleted,
            :quarterly,
            repo: repo,
          )
        end

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.quarterly", 0)

          perform_job
        end
      end

      context "quarterly configs that are active with active installations" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :quarterly,
            repo: repo,
          )
        end

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.quarterly", 1)

          perform_job
        end

        context "when the repo is paused", feature: :inactivity_pausing do
          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "doesn't enqueue a create scheduled update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end
    end

    context "with semiannually schedule" do
      let(:perform_job) { job.perform_now("semiannually") }

      it "instruments the scheduled job" do
        expect(MetricsClient).to receive(:time).
          with("enqueue_scheduled_updates_job.semiannually.time")

        perform_job
      end

      context "active daily configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :daily,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "active weekly configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :weekly,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "semiannually configs that are deleted" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :deleted,
            :semiannually,
            repo: repo,
          )
        end

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.semiannually", 0)

          perform_job
        end
      end

      context "semiannually configs that are active with active installations" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :semiannually,
            repo: repo,
          )
        end

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.semiannually", 1)

          perform_job
        end

        context "when the repo is paused", feature: :inactivity_pausing do
          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "doesn't enqueue a create scheduled update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end
    end

    context "with yearly schedule" do
      let(:perform_job) { job.perform_now("yearly") }

      it "instruments the scheduled job" do
        expect(MetricsClient).to receive(:time).
          with("enqueue_scheduled_updates_job.yearly.time")

        perform_job
      end

      context "active daily configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :daily,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "active weekly configs" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :weekly,
            repo: repo,
          )
        end

        it "doesn't enqueue a create scheduled update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "yearly configs that are deleted" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :deleted,
            :yearly,
            repo: repo,
          )
        end

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.yearly", 0)

          perform_job
        end
      end

      context "annually configs that are active with active installations" do
        let!(:update_config) do
          FactoryBot.create(
            :update_config,
            :active,
            :yearly,
            repo: repo,
          )
        end

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        it "instruments active update configs" do
          expect(MetricsClient).to receive(:gauge).
            with("scheduled_update_configs.yearly", 1)

          perform_job
        end

        context "when the repo is paused", feature: :inactivity_pausing do
          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "doesn't enqueue a create scheduled update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end
    end
  end
  # rubocop:enable RSpec/AnyInstance

  describe "filtering jobs by day and hour" do
    context "daily" do
      let(:update_run_time) { "07:00" }
      let(:timezone) { "UTC" }
      let(:weekly_update_run_day) { "saturday" }

      let(:perform_job) { job.perform_now("daily", now: now) }

      setup do
        FactoryBot.create(
          :update_config,
          :active,
          :daily,
          repo: repo,
          update_schedule_time_of_day: update_run_time,
          update_schedule_timezone: timezone,
          update_schedule_day_of_week: weekly_update_run_day
        )
      end

      context "at the weekend" do
        let(:now) { Time.utc(2018, 3, 24, 7, 0) }

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "in a timezone that means it's not the weekend" do
          let(:timezone) { "Pacific/Honolulu" }
          let(:update_run_time) { "21:00" }

          it "enqueues an update job" do
            expect { perform_job }.
              to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end

      context "scheduled for a different time" do
        let(:now) { Time.utc(2018, 3, 19, 7, 0) }
        let(:update_run_time) { "08:00" }

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "in a timezone that means that's now" do
          let(:timezone) { "Europe/Paris" }

          it "enqueues an update job" do
            expect { perform_job }.
              to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end
    end

    context "weekly" do
      let(:update_run_time) { "07:00" }
      let(:now) { Time.utc(2018, 3, 17, 7, 0) }
      let(:timezone) { "UTC" }
      let(:weekly_update_run_day) { "saturday" }

      let(:perform_job) { job.perform_now("weekly", now: now) }

      setup do
        FactoryBot.create(
          :update_config,
          :active,
          :weekly,
          repo: repo,
          update_schedule_time_of_day: update_run_time,
          update_schedule_timezone: timezone,
          update_schedule_day_of_week: weekly_update_run_day
        )
      end

      context "on our weekly update day" do
        let(:weekly_update_run_day) { "saturday" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "any other day" do
        let(:weekly_update_run_day) { "monday" }

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end
    end

    context "monthly" do
      let(:update_run_time) { "07:00" }
      let(:now) { Time.utc(2018, 3, 1, 7, 0) }
      let(:timezone) { "UTC" }
      let(:weekly_update_run_day) { "saturday" }

      let(:perform_job) { job.perform_now("monthly", now: now) }

      setup do
        FactoryBot.create(
          :update_config,
          :active,
          :monthly,
          repo: repo,
          update_schedule_time_of_day: update_run_time,
          update_schedule_timezone: timezone,
          update_schedule_day_of_week: weekly_update_run_day
        )
      end

      context "on our monthly update day" do
        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "scheduled for a different time" do
          let(:update_run_time) { "08:00" }

          it "doesn't enqueue an update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end

      context "any other day" do
        let(:now) { Time.utc(2018, 3, 2, 7, 0) }

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end
    end

    context "quarterly" do
      let(:update_run_time) { "07:00" }
      let(:now) { nil }
      let(:timezone) { "UTC" }

      let(:perform_job) { job.perform_now("quarterly", now: now) }

      setup do
        FactoryBot.create(
          :update_config,
          :active,
          :quarterly,
          repo: repo,
          update_schedule_time_of_day: update_run_time,
          update_schedule_timezone: timezone,
        )
      end

      context "on our quarterly update day (first quarter)" do
        let(:now) { Time.utc(2024, 1, 1, 7, 0) }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "scheduled for a different time" do
          let(:update_run_time) { "08:00" }

          it "doesn't enqueue an update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end

      context "on quarterly update day (first quarter)" do
        let(:now) { Time.utc(2018, 1, 1, 7, 0) }
        let(:update_run_time) { "07:00" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "scheduled for a different time" do
          let(:update_run_time) { "08:00" }

          it "doesn't enqueue an update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end

      context "on quarterly update day (second quarter)" do
        let(:now) { Time.utc(2018, 4, 1, 0, 0) }
        let(:update_run_time) { "00:00" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "scheduled for a different time" do
          let(:update_run_time) { "08:00" }

          it "doesn't enqueue an update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end

      context "any other day" do
        let(:now) { Time.utc(2018, 3, 2, 7, 0) }

        let(:update_run_time) { "07:00" }

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end
    end

    context "semiannually" do
      let(:update_run_time) { "07:00" }
      let(:now) { nil }
      let(:timezone) { "UTC" }

      let(:perform_job) { job.perform_now("semiannually", now: now) }

      setup do
        FactoryBot.create(
          :update_config,
          :active,
          :semiannually,
          repo: repo,
          update_schedule_time_of_day: update_run_time,
          update_schedule_timezone: timezone,
        )
      end

      context "on our semianually update day" do
        let(:now) { Time.utc(2024, 1, 1, 7, 0) }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "scheduled for a different time" do
          let(:update_run_time) { "08:00" }

          it "doesn't enqueue an update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end

      context "on semiannually update day different month" do
        let(:now) { Time.utc(2018, 1, 2, 7, 0) }
        let(:update_run_time) { "07:00" }

        it "enqueues an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "on semiannually update day (7th month)" do
        let(:now) { Time.utc(2018, 7, 1, 0, 0) }
        let(:update_run_time) { "00:00" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "any other day" do
        let(:now) { Time.utc(2018, 3, 2, 7, 0) }

        let(:update_run_time) { "07:00" }

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end
    end

    context "yearly" do
      let(:update_run_time) { "07:00" }
      let(:now) { nil }
      let(:timezone) { "UTC" }

      let(:perform_job) { job.perform_now("yearly", now: now) }

      setup do
        FactoryBot.create(
          :update_config,
          :active,
          :yearly,
          repo: repo,
          update_schedule_time_of_day: update_run_time,
          update_schedule_timezone: timezone,
        )
      end

      context "on yearly update day (start of year)" do
        let(:now) { Time.utc(2024, 1, 1, 7, 0) }
        let(:update_run_time) { "07:00" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end

        context "scheduled for a different time" do
          let(:update_run_time) { "08:00" }

          it "doesn't enqueue an update job" do
            expect { perform_job }.
              not_to have_enqueued_job(CreateScheduledUpdateJob)
          end
        end
      end

      context "on yearly update day different month" do
        let(:now) { Time.utc(2018, 1, 2, 7, 0) }
        let(:update_run_time) { "07:00" }

        it "enqueues an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "on yearly update different day" do
        let(:now) { Time.utc(2018, 2, 1, 7, 0) }

        let(:update_run_time) { "07:00" }

        it "doesn't enqueue an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end
    end

    context "cron" do
      let(:timezone) { "UTC" }
      let(:perform_job) { job.perform_now("cron", now: now) }

      setup do
        FactoryBot.create(
          :update_config,
          :active,
          :cron,
          repo: repo,
          update_schedule_cron_expression: cron_expression,
          update_schedule_timezone: timezone
        )
      end

      context "cron job schedule : daily at 7 AM" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 7) }
        let(:cron_expression) { "0 7 * * *" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : every other month" do
        let(:now) { Time.utc(2024, 3, 1, 0, 0) }
        let(:cron_expression) { "0 0 1 */2 *" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : daily at 5 PM" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 17) }
        let(:cron_expression) { "0 17 * * *" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : daily at 5 PM with timezone" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 17, 0) }
        let(:cron_expression) { "0 17 * * *" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : daily at 6 PM with timezone" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 17, 0) }
        let(:cron_expression) { "0 16 * * *" }

        it "does not enqueues an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : daily at 13:25" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 13, 25) }
        let(:cron_expression) { "25 13 * * *" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : every tuesday at 3 AM" do
        let(:now) do
          get_desired_day(Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 3), "tuesday")
        end

        let(:cron_expression) { "every tuesday at 3 AM" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : every thursday at 1 PM" do
        let(:now) do
          get_desired_day(Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 13), "thursday")
        end

        let(:cron_expression) { "0 13 * * 4" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : every monday and friday at 5pm" do
        let(:now) do
          get_desired_day(Time.utc(2025, 2, 3, 17), "monday")
        end

        let(:cron_expression) { "every monday and friday at 5pm" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : every day at 16:00" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 16) }
        let(:cron_expression) { "every day at 16:00" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : daily (defaults to 00:00)" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 0) }
        let(:cron_expression) { "@daily" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : weekly (defaults to 00:00 on sunday)" do
        let(:now) do
          get_desired_day(Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 0), "sunday")
        end
        let(:cron_expression) { "@weekly" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : midnight (defaults to 00:00 everyday)" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 0) }
        let(:cron_expression) { "@midnight" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : 5 minutes after midnight everyday" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 0, 5) }
        let(:cron_expression) { "5 0 * * *" }

        it "enqueues an update job" do
          expect { perform_job }.
            to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end

      context "cron job schedule : 5 minutes after midnight everyday but in a different timezone" do
        let(:now) { Time.utc(Time.zone.now.year, Time.zone.now.month, Time.zone.now.day, 0, 5) }
        let(:cron_expression) { "5 0 * * *" }
        let(:timezone) { "Pacific/Honolulu" }

        it "enqueues an update job" do
          expect { perform_job }.
            not_to have_enqueued_job(CreateScheduledUpdateJob)
        end
      end
    end

    def get_desired_day(time, required_day)
      loop do
        break if time.strftime("%A").downcase == required_day

        time += 1.day
      end
      time
    end

    context "with a bad timezone" do
      let(:now) { Time.utc(2018, 3, 22, 7, 0) }
      let(:perform_job) { job.perform_now("daily", now: now) }

      # rubocop:disable RSpec/AnyInstance
      before do
        FactoryBot.create(
          :update_config,
          :active,
          :daily,
          repo: repo,
          update_schedule_time_of_day: "07:00",
          update_schedule_timezone: "UTC"
        )
        allow_any_instance_of(UpdateConfig).to receive(:update_schedule_timezone).and_return("Fake/Timezone")
      end
      # rubocop:enable RSpec/AnyInstance

      it "enqueues the job instead of raising an error" do
        expect { perform_job }.
          to have_enqueued_job(CreateScheduledUpdateJob)
      end
    end
  end

  describe "#enqueue_scheduled_update" do
    let(:update_config) { create(:update_config, :active, repo: repo) }
    let(:now) { Time.now.utc }
    let(:job_instance) { described_class.new }
    let(:interval_verification) { instance_double(ScheduledJobs::EnqueueScheduledUpdates::IntervalVerification) }

    before do
      allow(ScheduledJobs::EnqueueScheduledUpdates::IntervalVerification).
        to receive(:new).
        and_return(interval_verification)
      allow(interval_verification).to receive(:matches_config?).and_return(true)
    end

    it "passes enqueue_scheduled_update_id to CreateScheduledUpdateJob" do
      expect(CreateScheduledUpdateJob).to receive(:perform_later).with(
        hash_including(
          update_config_id: update_config.id,
          enqueue_scheduled_update_id: kind_of(String)
        )
      )
      job_instance.send(:enqueue_scheduled_update, [update_config], now)
    end
  end
end
