# frozen_string_literal: true

module ScheduledJobs
  class EnqueueScheduledUpdates < ApplicationScheduledJob
    queue_as :scheduled_updates
    default_retries_for_idempotent_jobs

    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"
    QUARTERLY = "quarterly"
    SEMIANNUALLY = "semiannually"
    YEARLY = "yearly"
    CRON = "cron"

    class Daily < EnqueueScheduledUpdates
      schedule interval: 1.hour

      def perform
        super(DAILY)
      end
    end

    class Weekly < EnqueueScheduledUpdates
      schedule interval: 1.hour

      def perform
        super(WEEKLY)
      end
    end

    class Monthly < EnqueueScheduledUpdates
      schedule interval: 1.hour

      def perform
        super(MONTHLY)
      end
    end

    class Cron < EnqueueScheduledUpdates
      schedule interval: 1.hour

      def perform
        Rails.logger.info "Initiating EnqueueScheduledUpdates with cron"
        super(CRON)
      end
    end

    class Quarterly < EnqueueScheduledUpdates
      schedule interval: 1.hour

      def perform
        Rails.logger.info "Initiating EnqueueScheduledUpdates with quarterly option"
        super(QUARTERLY)
      end
    end

    class Semiannually < EnqueueScheduledUpdates
      schedule interval: 1.hour

      def perform
        Rails.logger.info "Initiating EnqueueScheduledUpdates with Semiannually option"
        super(SEMIANNUALLY)
      end
    end

    class Yearly < EnqueueScheduledUpdates
      schedule interval: 1.hour

      def perform
        Rails.logger.info "Initiating EnqueueScheduledUpdates with Yearly option"
        super(YEARLY)
      end
    end

    VALID_SCHEDULES = [DAILY, WEEKLY, MONTHLY, QUARTERLY, SEMIANNUALLY, YEARLY, CRON].freeze

    WEEKDAYS = %w(monday tuesday wednesday thursday friday).freeze

    class IntervalVerification
      attr_reader :update_config

      def initialize(update_config:, started_at:)
        @update_config = update_config
        @started_at = started_at
      end

      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
      def matches_config?
        case update_config.update_schedule
        when "daily"
          weekday? && correct_hour?
        when "weekly"
          correct_day_of_week? && correct_hour?
        when "monthly"
          first_of_month? && correct_hour?
        when "quarterly"
          Rails.logger.info "Initiating Quarterly job scheduler"
          quarter_month? && first_of_month? && correct_hour?
        when "semiannually"
          Rails.logger.info "Initiating Semiannually job scheduler"
          semiannually_month? && first_of_month? && correct_hour?
        when "yearly"
          Rails.logger.info "Initiating Yearly job scheduler"
          yearly? && first_of_month? && correct_hour?
        when "cron"
          Rails.logger.info "Initiating Cron job scheduler"
          cronjob_correct_time?
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity

      private

      def correct_hour?
        local_time.hour == update_config.update_schedule_time_of_day.hour
      end

      def weekday?
        WEEKDAYS.include?(local_time.strftime("%A").downcase)
      end

      def correct_day_of_week?
        local_time.strftime("%A").downcase ==
          update_config.update_schedule_day_of_week
      end

      def first_of_month?
        local_time.day == 1
      end

      def quarter_month?
        [1, 4, 7, 10].include?(local_time.month)
      end

      def semiannually_month?
        [1, 7].include?(local_time.month)
      end

      def yearly?
        [1].include?(local_time.month)
      end

      def cronjob_correct_time?
        if update_config.update_schedule_cron_expression.nil? ||
           update_config.update_schedule_cron_expression.to_s.strip.empty?
          Rails.logger.info "Error while evaluating cron expression"
          return false
        end

        Dependabot::Logger.info(
          msg: "Matching cron job expression ",
          cron_expression: update_config.update_schedule_cron_expression,
          local_time: local_time.hour,
          "gh.dependabot_api.update_config.id": update_config.id,
        )

        update_config.cronjob_match?(local_time)
      end

      def local_time
        @local_time ||= TZInfo::Timezone.get(
          update_config.update_schedule_timezone
        ).utc_to_local(@started_at)
      rescue TZInfo::InvalidTimezoneIdentifier
        @local_time = @started_at
      end
    end

    def perform(schedule = WEEKLY, now: Time.now.utc) # rubocop:disable Metrics/MethodLength
      raise ArgumentError, "Invalid schedule: '#{schedule}'" unless VALID_SCHEDULES.include?(schedule)

      if Dependabot::Application.monolith_feature_enabled?(feature: :run_timed_enqueue_scheduled_updates_job,
                                                           actor: nil)
        EnqueueScheduledUpdatesTimed.perform_later(schedule_type: schedule, initial_start: now)
        return
      end

      Rails.logger.info "Enqueuing update jobs for '#{schedule}' schedules."
      total_active = 0
      total_enqueued = 0

      MetricsClient.time("enqueue_scheduled_updates_job.#{schedule}.time") do
        scheduled_update_configs(schedule).in_batches do |update_configs|
          # The active scope is expensive to apply to a broad query so we apply it to each
          # batch instead.
          active_update_configs = UpdateConfig.
                                  active.where(id: update_configs.pluck(:id))
          enqueued_count = enqueue_scheduled_update(active_update_configs, now)
          # Only count truthy returns from the enqueue batch
          total_enqueued += enqueued_count
          total_active += active_update_configs.count
        end
      end

      Rails.logger.info "Enqueued #{total_enqueued} update jobs for '#{schedule}' schedules."
      MetricsClient.gauge("scheduled_update_configs.#{schedule}",
                          total_active)

      MetricsClient.gauge("enqueue_scheduled_updates_job.processed", total_active, tags: { schedule: schedule })
      MetricsClient.gauge("enqueue_scheduled_updates_job.enqueued", total_enqueued, tags: { schedule: schedule })
    rescue StandardError => e
      Rails.logger.error "Failed enqueuing update jobs for '#{schedule}' schedules. Error: #{e.message}"
      raise
    end

    private

    def enqueue_scheduled_update_id
      @enqueue_scheduled_update_id ||= SecureRandom.uuid
    end

    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/BlockLength
    def enqueue_scheduled_update(update_configs, now)
      MetricsClient.time("enqueue_scheduled_updates_job.enqueue_scheduled_update.time") do
        enqueued_count = 0
        update_configs.each do |update_config|
          interval = IntervalVerification.new(update_config: update_config,
                                              started_at: now)
          next unless MetricsClient.time("enqueue_scheduled_updates_job.interval_verification.time") do
            interval.matches_config?
          end

          set_args = {}

          if update_config.repo.config_feature_enabled?(:spread_out_updates)
            set_args[:wait] = rand(59).minutes + rand(59).seconds
          elsif update_config.repo.config_feature_enabled?(:spread_out_updates_time_of_day)
            time = Time.zone.now
            unless update_config.update_schedule_time_of_day.nil?
              time = time.change(
                min: update_config.update_schedule_time_of_day.min,
                sec: rand(59).seconds
              )
            end
            set_args[:wait_until] = time
          end

          job = CreateScheduledUpdateJob
          job = job.set(set_args) unless set_args.empty?

          MetricsClient.time("enqueue_scheduled_updates_job.perform_later.time") do
            job.perform_later(
              update_config_id: update_config.id,
              enqueue_scheduled_update_id: enqueue_scheduled_update_id
            )
          end

          enqueued_count += 1
        end
        enqueued_count
      end
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/BlockLength

    def scheduled_update_configs(schedule)
      where_condition = { update_schedule: schedule }
      where_condition[:repo] = { paused_at: nil }

      UpdateConfig.joins(:repo).where(where_condition)
    end
  end
end
