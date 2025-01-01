# typed: strict
# frozen_string_literal: true

class GitHubModelsJob < ApplicationJob

  queue_as :github_models

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Don't enqueue models jobs unles GitHub Models is enabled
  around_enqueue do |_job, block|
    block.call if GitHub.models_enabled?
  end

  around_perform do |job, block|
    job_name = job.class.name
    flag_enabled = job.flag_enabled

    GitHub.logger.with_named_tags(
      "code.function" => __method__.to_s,
      "code.namespace" => self.class.name,
      "gh.github_models.flag_enabled" => flag_enabled,
      "gh.job.id" => job.job_id,
      "gh.job.name" => job_name,
      "gh.job.arguments" => job.arguments,
      "gh.job.executions" => job.executions,
    ) do
      GitHub.logger.info("#{flag_enabled ? "Performing" : "Skipping"} #{job_name}")
      job.collect_metrics do
        if flag_enabled
          with_read { block.call }
        end
      end
    end
  end

  sig { params(flags: T.any(Symbol, T::Array[Symbol])).void }
  def self.gate_with_feature_flag(flags)
    @flags = T.let(Array.wrap(flags), T.nilable(T::Array[Symbol]))
  end

  sig { returns(T.nilable(T::Array[Symbol])) }
  def self.flags
    @flags
  end

  sig { returns(T::Boolean) }
  def flag_enabled
    # if the flags weren't set, we won't check
    return true unless self.class.flags

    T.must(self.class.flags).all? { |flag| GitHub.flipper[flag].enabled? }
  end

  protected

  sig do
    type_parameters(:A).params(
      block: T.proc.returns(T.type_parameter(:A)),
    ).returns(T.type_parameter(:A))
  end
  def collect_metrics(&block)
    GitHub.tracer.in_span(name, kind: :internal) do
      begin
        GitHub.dogstats.distribution_time("#{name}.latency") do
          yield
        end
        GitHub.dogstats.increment(name)
      rescue => e # rubocop:todo Lint/GenericRescue
        GitHub.dogstats.increment "#{name}.errors"
        raise e
      end
    end
  end

  sig { returns(String) }
  def name
    self.class.name.to_s.underscore
  end
end
