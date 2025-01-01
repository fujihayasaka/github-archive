# typed: strict
# frozen_string_literal: true

class CopilotJob < ApplicationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :copilot

  # Don't enqueue copilot jobs in GHES
  around_enqueue do |_job, block|
    block.call if GitHub.copilot_enabled?
  end

  around_perform do |job, block|
    job_name = job.class.name
    flag_enabled = job.flag_enabled

    GitHub.logger.with_named_tags(
      "code.function" => __method__.to_s,
      "code.namespace" => self.class.name,
      "gh.copilot.job_name" => job_name,
      "gh.copilot.job_arguments" => job.arguments,
      "gh.copilot.flag_enabled" => flag_enabled,
    ) do
      GitHub.logger.info("#{flag_enabled ? "Performing" : "Skipping"} #{job_name}")
      job.collect_metrics do
        if flag_enabled
          with_read do
            block.call
          end
        end
      end
    end
  end

  sig { params(waiting_period: ActiveSupport::Duration, kwargs: T.untyped).void } # rubocop:disable Sorbet/ForbidTUntyped
  def self.perform_after_waiting_period(waiting_period, **kwargs)
    set(wait: waiting_period).perform_later(**kwargs)
  end

  sig { params(value: T::Boolean).void }
  def self.skip_chatterbox_for_errors(value)
    @skip_chatterbox_for_errors = T.let(value, T.nilable(T::Boolean))
  end

  sig { returns(T.nilable(T::Boolean)) }
  def self.skip_chatterbox_for_errors?
    @skip_chatterbox_for_errors
  end

  sig { params(flags: T.any(Symbol, T::Array[Symbol])).void }
  def self.gate_with_feature_flag(flags)
    flags = Array.wrap(flags) unless flags.is_a?(Array)
    @flags = T.let(flags, T.nilable(T::Array[Symbol]))
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

  sig { params(message: String, details: T::Hash[Symbol, T.untyped]).void } # rubocop:disable Sorbet/ForbidTUntyped
  def handle_error(message, details = {})
    handle_copilot_error(Copilot::Errors::CopilotError.new(message), details)
  end

  sig { params(error: Copilot::Errors::CopilotError, details: T::Hash[Symbol, T.untyped]).void } # rubocop:disable Sorbet/ForbidTUntyped
  def handle_copilot_error(error, details = {})
    Copilot::ErrorReporter.report!(
      error,
      extra_details: details,
    )

    GitHub.dogstats.increment "#{name}.errors"

    chatterbox_say("Copilot job #{name} failed: #{error.message}") unless self.class.skip_chatterbox_for_errors?

    GitHub.logger.info(error.message)
  end

  sig { params(msg: String).void }
  def chatterbox_say(msg)
    Copilot::Helpers.chatterbox_say(msg)
  end

  sig { returns(T::Hash[Symbol, T::Array[Integer]]) }
  def org_and_biz_ids_through_seats
    organization_ids = Copilot::Seat.where.not(organization_id: nil).distinct.pluck(:organization_id)
    entity_ids = { business_ids: Set.new, organization_ids: Set.new }

    ::Organization.includes(:business).where(id: organization_ids).inject(entity_ids) do |entity_ids, org|
      next entity_ids unless ensure_org?(org)

      if org.business.present?
        entity_ids[:business_ids] << T.must(org.business).id
      else
        if copilot_enabled_for_org?(org)
          entity_ids[:organization_ids] << org.id
        else
          handle_copilot_error(Copilot::Errors::OrganizationResolutionError.new("#{Copilot.business_product_name} is not enabled for organization"), { "gh.organization.id" => org.id })
        end
      end
      entity_ids
    end.sort.to_h
  end

  private

  sig { params(org: ::Organization).returns(T::Boolean) }
  def copilot_enabled_for_org?(org)
    begin
      Copilot::Organization.new(org).copilot_enabled?
    rescue # rubocop:todo Lint/GenericRescue
      handle_copilot_error(Copilot::Errors::OrganizationResolutionError.new("Potential error creating configuration for organization"), { "gh.organization.id" => org.id })
      false
    end
  end

  sig { params(org: T.nilable(::Organization)).returns(T::Boolean) }
  def ensure_org?(org)
    if org.nil?
      handle_copilot_error(Copilot::Errors::OrganizationResolutionError.new("Error finding organization"))
      false
    else
      true
    end
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
