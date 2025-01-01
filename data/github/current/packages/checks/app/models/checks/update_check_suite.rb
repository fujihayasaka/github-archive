# typed: true
# frozen_string_literal: true

class Checks::UpdateCheckSuite
  include GitHub::Tracing

  attr_reader :check_suite, :update_properties

  trace_method(
    :call,
    span_attribute_extractor: -> (instance, *_args, **_kwargs) do
      {
        "gh.repo.id" => instance.check_suite.repository_id,
        "gh.check_suite.id" => instance.check_suite.id,
      }
    end
  )
  trace_method :update_annotations
  trace_method :update_artifacts
  trace_method :update_check_suite
  trace_method :update_concurrency
  trace_method :save_check_suite
  trace_method :update_conclusion

  def self.call(check_suite:, update_properties:)
    new(
      check_suite: check_suite,
      update_properties: update_properties
    ).call
  end

  def initialize(check_suite:, update_properties:)
    @check_suite = check_suite
    @update_properties = update_properties
  end

  def call
    update_annotations(update_properties[:annotations])
    update_artifacts(update_properties[:artifacts])

    repository = Repository.instantiate("id" => check_suite.repository_id)

    if GitHub.flipper[:check_suite_update_conclusion_with_conditional_query].enabled?(repository)
      check_suite_update_properties = build_check_suite_update_properties(update_properties)
      update_workflow_run_concurrency(update_properties)
      save_check_suite_updates(check_suite_update_properties)
    else
      update_completed_log_url(update_properties[:check_suite_updates])
      update_concurrency(update_properties[:concurrency])
      update_conclusion(update_properties[:conclusion])

      save_check_suite
    end
  end

  private

  def update_annotations(annotations)
    return if annotations.blank?
    Checks::CreateCheckAnnotations.call(check_suite: check_suite, annotations: annotations)
  end

  def update_artifacts(artifacts)
    return if artifacts.blank?

    repository = Repository.instantiate("id" => check_suite.repository_id)

    if GitHub.flipper[:checks_create_check_artifacts_job_enabled].enabled?(repository)
      CreateArtifactsJob.perform_later(check_suite_id: check_suite.id, artifacts: artifacts)
    else
      Checks::CreateArtifacts.call(check_suite: check_suite, artifacts: artifacts)
    end
  end

  def build_check_suite_update_properties(update_properties)
    check_suite_update_properties = {}

    check_suite_updates = update_properties.fetch(:check_suite_updates, {})
    if check_suite_updates[:completed_log_url].present?
      check_suite_update_properties.merge!({ completed_log_url: check_suite_updates[:completed_log_url] })
    end

    concurrency = update_properties[:concurrency]
    if concurrency.present? && check_suite.workflow_run.present?
      check_suite_update_properties.merge!({ status: "pending" })
    end

    conclusion = update_properties[:conclusion]
    if conclusion.present?
      check_suite_update_properties.merge!({ conclusion: conclusion, status: "completed", completed_at: Time.zone.now })
    end

    check_suite_update_properties
  end

  def update_workflow_run_concurrency(update_properties)
    concurrency = update_properties[:concurrency]
    if concurrency.present? && check_suite.workflow_run.present?
      check_suite.workflow_run.update(concurrency: JSON.generate(concurrency))
    end
  end

  def save_check_suite_updates(check_suite_update_properties)
    GitHub.logger.info("saving check suite updates", {
      "code.namespace" => self.class.name,
      "code.function" => "save_check_suite_updates",
      "update_properties" => update_properties,
      "check_suite_updates" => check_suite_update_properties,
    })

    check_suite.update_when_not_completed(check_suite_update_properties)
  end

  def update_completed_log_url(check_suite_updates)
    return if check_suite_updates.blank?

    check_suite.completed_log_url = check_suite_updates[:completed_log_url] if check_suite_updates[:completed_log_url]
  end

  def save_check_suite
    GitHub.logger.info("saving check suite after update", {
      "code.namespace" => self.class.name,
      "code.function" => "save_check_suite",
      "gh.check_suite.conclusion" => check_suite.conclusion,
      "gh.check_suite.status" => check_suite.status,
      "update_properties" => update_properties,
    })

    check_suite.save!
  end

  def update_concurrency(concurrency)
    return if check_suite.workflow_run.blank? || concurrency.blank?

    check_suite.status = CheckSuite.statuses[:pending]
    check_suite.workflow_run.update(concurrency: JSON.generate(concurrency))
  end

  def update_conclusion(conclusion)
    return unless conclusion.present?

    conclusion_enum = CheckSuite.conclusions.find { |_, value| value == conclusion }
    new_conclusion = conclusion_enum&.first

    GitHub.logger.info("updating check suite conclusion from #{check_suite.conclusion || 'nil'} to #{new_conclusion}", {
      "code.namespace" => self.class.name,
      "code.function" => "update_conclusion",
      "gh.check_suite.previous_conclusion" => check_suite.conclusion,
      "gh.check_suite.new_conclusion" => new_conclusion,
      "gh.check_suite.previous_status" => check_suite.status,
      "gh.check_suite.new_status" => "completed", # Status will be set to completed when a concliusion is set
      "update_properties" => update_properties,
    })

    # We're going to save the check suite after this step so we don't have to persist
    # the conclusion immediately. This saves us a whole round of callbacks.
    check_suite.set_complete_explicitly!(conclusion, run_callbacks: false)
  end
end
