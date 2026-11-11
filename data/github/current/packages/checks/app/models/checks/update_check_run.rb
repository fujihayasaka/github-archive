# typed: true
# frozen_string_literal: true

class Checks::UpdateCheckRun
  include GitHub::Tracing

  MAX_NUMBER_OF_ANNOTATIONS = 50
  STATS_PREFIX = "checks/update_check_run"

  attr_reader :check_run, :update_properties

  trace_method(
    :call,
    span_attribute_extractor: -> (instance, *_args, **_kwargs) do
      {
        "gh.repo.id" => instance.check_run.repository_id,
        "gh.check_run.id" => instance.check_run.id,
        "gh.actions.workflow_job_run.is_cloned" => instance.update_properties.fetch(:is_cloned_from_previous_run, false),
      }
    end
  )

  trace_method :update_check_run
  trace_method :update_workflow_job_run
  trace_method :save_check_run
  trace_method :upsert_check_run_steps
  trace_method :update_merge_queue_status
  trace_method :update_deployment

  def self.call(check_run:, update_properties:)
    new(
      check_run: check_run,
      update_properties: update_properties
    ).call
  end

  def initialize(check_run:, update_properties:)
    @check_run = check_run
    @update_properties = update_properties
  end

  def call
    raise max_annotations_error if exceeds_max_annotations?

    update_check_run
    upsert_check_run_steps
    update_workflow_job_run
    save_check_run
    update_merge_queue_status
    update_deployment

    check_run
  end

  private

  def max_annotations_error
    Checks::Errors::MaxAnnotationsExceeded.new("Annotations exceeds maximum quantity.")
  end

  def exceeds_max_annotations?
    update_properties[:annotations].length > MAX_NUMBER_OF_ANNOTATIONS
  end

  def update_check_run
    check_run.assign_attributes(update_properties[:check_run_updates].compact)

    update_properties[:annotations] = Checks::CreateCheckAnnotations.remove_invalid_annotations(
      update_properties[:annotations],
      check_run.repository_id,
      STATS_PREFIX,
      self.class.name,
      "call"
    )
    check_run.annotations.build(update_properties[:annotations])
  end

  def save_check_run
    GitHub.logger.info("saving check run", {
      "code.namespace" => self.class.name,
      "code.function" => "save_check_run",
      "gh.check_suite.id" => check_run.check_suite_id,
      "update_properties" => update_properties,
    })

    check_run.save!
  end

  def upsert_check_run_steps
    is_cloned_from_previous_run = update_properties.fetch(:is_cloned_from_previous_run, false)
    check_steps = update_properties.fetch(:check_run_steps, [])

    return if check_steps.empty? || check_run.disable_dotcom_check_steps_writes?

    repository = Repository.instantiate("id" => check_run.repository_id)

    Checks::CreateCheckSteps.call(
      check_run: check_run,
      is_cloned_from_previous_run: is_cloned_from_previous_run,
      check_steps: check_steps,
    )
  end

  def update_workflow_job_run
    return if update_properties[:workflow_job_run].blank? || check_run.workflow_job_run.nil?

    check_run.workflow_job_run.assign_attributes(update_properties[:workflow_job_run].compact)

    if update_properties[:concurrency].present?
      check_run.workflow_job_run.concurrency = JSON.generate(update_properties[:concurrency])
    end

    check_run.workflow_job_run.save!
  end

  def update_merge_queue_status
    MergeQueues.execute_from_sha!(check_run.repository, check_run.head_sha)
  end

  def update_deployment
    deployment = update_properties.dig(:deployment_environments)
    return if deployment.blank?

    is_cloned = update_properties.fetch(:is_cloned_from_previous_run, false)

    # If we get an invalid environment, we should still pass back the updated check run which has already been saved
    # We might want to skip this step as well since it's unclear if we ever want to update the environment
    check_run.create_deployment(deployment[:name], is_cloned: is_cloned) if deployment[:name].present?
    check_run.create_deployment_status(deployment[:url]) if check_run.deployment.present?
  rescue ActiveRecord::RecordInvalid
  end
end
