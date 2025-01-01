# typed: true
# frozen_string_literal: true

class Checks::CreateCheckSteps
  attr_reader :check_run, :check_steps, :is_cloned_from_previous_run, :steps_batch_size, :repository

  STATS_PREFIX = "checks/create_check_steps"
  STEPS_BATCH_SIZE_DEFAULT = 120 # Our average varies between 80 and 120

  def self.call(check_run:, check_steps:, is_cloned_from_previous_run:)
    upsert_batch_size = STEPS_BATCH_SIZE_DEFAULT

    if FeatureFlag.vexi.enabled?(:check_steps_upsert_batch_size_25, default: false)
      upsert_batch_size = 25
    end
    if FeatureFlag.vexi.enabled?(:check_steps_upsert_batch_size_50, default: true)
      upsert_batch_size = 50
    end
    if FeatureFlag.vexi.enabled?(:check_steps_upsert_batch_size_75, default: false)
      upsert_batch_size = 75
    end
    if FeatureFlag.vexi.enabled?(:check_steps_upsert_batch_size_100, default: false)
      upsert_batch_size = 100
    end

    new(
      check_run: check_run,
      check_steps: check_steps,
      is_cloned_from_previous_run: is_cloned_from_previous_run,
      steps_batch_size: upsert_batch_size,
    ).call
  end

  def initialize(check_run:, check_steps:, is_cloned_from_previous_run:, steps_batch_size:)
    @check_run = check_run
    @check_steps = check_steps
    @is_cloned_from_previous_run = is_cloned_from_previous_run
    @steps_batch_size = steps_batch_size

    # Only used for actions_split_check_step_transaction feature flag
    @repository = Repository.instantiate("id" => @check_run.repository_id)
  end

  def call
    return if check_steps.blank?

    stats_tags = ["is_cloned_from_previous_run:#{is_cloned_from_previous_run}"]

    GitHub.dogstats.count("#{STATS_PREFIX}.check_steps_count", check_steps.count, tags: stats_tags)

    GitHub.dogstats.time("#{STATS_PREFIX}.create_steps_duration", tags: stats_tags) do
      GitHub.tracer.in_span("CreateCheckSteps::call", kind: :internal) do |_span|
        GitHub.tracer.in_span("CreateCheckSteps::upsert_check_steps", kind: :internal) do |_span|
          upsert_check_steps
        end
      end
    end
  end

  private

  def upsert_check_steps
    steps_hash = check_run.steps.index_by(&:external_id)

    if is_cloned_from_previous_run
      previous_check_run_steps = previous_check_steps
    end

    if FeatureFlag.vexi.enabled?(:actions_split_check_step_transaction, repository, default: true)
      check_steps.each_slice(steps_batch_size) do |steps_batch|
        CheckStep.transaction do
          steps_batch.each do |input_step|
            upsert_step(steps_hash, input_step, previous_check_run_steps)
          end
        end
      end
    else
      CheckStep.transaction do
        check_steps.each do |input_step|
          upsert_step(steps_hash, input_step, previous_check_run_steps)
        end
      end
    end
  end

  def upsert_step(steps_hash, input_step, previous_check_run_steps)
    check_step = steps_hash[input_step[:external_id]]
    is_check_step_update = check_step.present?

    check_step ||= CheckStep.new(
      # Pass check_run rather than check_run_id to avoid unnecessary db lookups
      check_run: check_run,
      number: input_step[:number],
      repository_id: check_run.repository_id,
    )

    check_step.name = input_step[:name] if input_step[:name].present?
    check_step.completed_at = input_step[:completed_at] if input_step[:completed_at].present?
    check_step.started_at = input_step[:started_at] if input_step[:started_at].present?
    check_step.status = input_step[:status] if input_step[:status].present?
    check_step.conclusion = input_step[:conclusion] if input_step[:conclusion].present?
    check_step.external_id = input_step[:external_id] if input_step[:external_id].present?
    check_step.number = input_step[:number] if input_step[:number].present?

    if input_step[:completed_log].present?
      check_step.completed_log_url = input_step.dig(:completed_log, :url).to_s
      check_step.completed_log_lines = input_step.dig(:completed_log, :lines)
    elsif is_cloned_from_previous_run && previous_check_run_steps
      previous_step = previous_check_run_steps[input_step[:number]]

      if previous_step
        check_step.completed_log_url = previous_step.completed_log_url
        check_step.completed_log_lines = previous_step.completed_log_lines
      end
    end

    GitHub.dogstats.time("#{STATS_PREFIX}.create_single_step_duration", tags: ["is_check_step_update:#{is_check_step_update}"]) do
      check_step.save!
    end
  end

  def previous_check_steps
    GitHub.tracer.in_span("CreateCheckSteps::previous_check_steps", kind: :internal) do |_span|
      previous_check_run = check_run.check_suite.check_runs.with_display_name(check_run.display_name).where.not(id: check_run.id).last
      previous_check_run.steps.index_by(&:number) if previous_check_run
    end
  end
end
