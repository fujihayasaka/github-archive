# typed: true
# frozen_string_literal: true

module Reachability::ActionsWorkflow
  extend self
  include Kernel

  class InputsTooLarge < StandardError; end
  class UnableToLaunch < StandardError; end

  # Public: Creates a reachability analysis actions workflow run.
  #
  # actor - The actor initiating the workflow run.
  # repo - The repository to run the workflow against.
  # sha - The commit_sha to analyze.
  # job_id - the job_id that initiated the workflow run
  #
  # Returns the worklfow run id.
  # Raises InputsTooLarge if the Action inputs are too large.
  # Raises UnableToLaunch if for some reason we were unable to launch the workflow run.
  def create_workflow_run(actor:, repo:, sha:, job_id: "", integration_name: "github-advanced-security")

    inputs = {
      "job_id": job_id,
    }

    if inputs.to_json.length > MYSQL_TEXT_FIELD_LIMIT
      raise InputsTooLarge, "Action workflow inputs too large"
    end

    workflow = dynamic_workflow_yaml

    installation = repo.actions_app_installation

    result = ActiveRecord::Base.connected_to(role: :writing) do
      repo.run_dynamic_workflow(
        actor: actor,
        workflow: workflow,
        ref: sha,
        inputs: inputs,
        workflow_name: "Reachability Analysis",
        slug: "reachability",
        integration_name: integration_name, # TODO when we have a GitHub app
        entry_point: :reachability_actions_helper_run_dynamic_workflow
      )
    end

    unless result
      raise UnableToLaunch, "Unable to launch reachability run. No response from launch run_dynamic_workflow."
    end

    unless result.call_succeeded?
      message = result&.options ? result.options[:message] : nil
      raise UnableToLaunch, "Unable to launch reachability run. #{message}"
    end

    result.value.workflow_run_id
  end

  def dynamic_workflow_yaml
    # Read the workflow file from disk
    file_path = File.join(File.dirname(__FILE__), "workflow.yml")
    File.read(file_path)
  end
end
