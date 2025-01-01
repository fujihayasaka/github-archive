# typed: true
# frozen_string_literal: true

module StacksSteps
  class WorkflowDispatchStep < Step
    WORKFLOW_DISPATCH_INPUT_LIMIT = 100

    def self.validate_inputs(inputs_hash, repo:, actor:, stack_repo: nil)
      method_name = "#{self.class.name}##{__method__}"
      if inputs_hash.has_key?("workflow_path")
        begin
          # TODO: Validate workflow in ref instead of default branch when we start supporting ref
          workflow_path = ".github/workflows/#{ inputs_hash["workflow_path"] }"
          unless inputs_hash.has_key?("ref")
            raise StandardError.new("Missing ref to '#{ workflow_path }'.")
          end
          unless inputs_hash["ref"].is_a?(String)
            raise StandardError.new("Invalid clone ref to '#{ workflow_path }'.")
          end
          ref = inputs_hash["ref"]
          parsed_workflow = get_parsed_workflow(stack_repo, workflow_path, ref)
        rescue StandardError => e # rubocop:todo Lint/GenericRescue
          # disabling rescue_lint as we are re-raising with a wrapped error
          GitHub::Logger.log(fn: method_name,
            message: e.message)
          raise Errors::ValidationError.new(e.message)
        end
      else
        GitHub::Logger.log(fn: method_name,
          message: "Missing {workflow: workflow_path} in input")
        raise Errors::MissingKeyError.new("workflow_path")
      end
    end

    def self.get_parsed_workflow(repo, workflow_path, ref)
      raise StandardError.new("Missing reference to the stack template repo.") if repo.nil?
      parsed_workflow = Actions::ParsedWorkflow.parse_from_yaml(repo, workflow_path, ref)
      raise StandardError.new("Invalid or missing workflow file '#{ workflow_path }'.") if parsed_workflow.nil?
      raise StandardError.new("No workflow_dispatch trigger found in '#{ workflow_path }'.") unless parsed_workflow.has_workflow_dispatch_trigger?
      parsed_workflow
    end

    def self.get_step_name
      "WorkflowDispatchStep"
    end

    def get_step_group
      StepGroup.workflow_run
    end

    def get_step_metadata
      data = super
      inputs_hash = self.inputs
      if inputs_hash["workflow_path"].include?(".github/workflows")
        data["workflow_path"] = inputs_hash["workflow_path"]
      else
        data["workflow_path"] = ".github/workflows/#{ inputs_hash["workflow_path"] }"
      end
      data
    end

    def run(repo:, actor:)
      inputs_hash = self.inputs
      begin
        repo.unlock_excluding_descendants! if repo.locked_on_stacks_config?
        dispatch_workflow(repo, actor, inputs_hash)
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        # disabling rescue_lint as we are re-raising with a wrapped error
        GitHub::Logger.log_exception(
          { fn: "#{self.class.name}##{__method__}", repo_id: repo.id }, e)
        raise Errors::WorkflowDispatchError.new(e.message)
      end
    end

    def cleanup(repo:, actor:)
    end

    private

    def get_workflow_input_keys(parsed_workflow)
      return [] if parsed_workflow.workflow_dispatch_inputs.nil?
      parsed_workflow.workflow_dispatch_inputs.keys
    end

    def validate_limits(workflow_inputs)
      raise StandardError.new("Workflow inputs are too large") if workflow_inputs.to_json.length > MYSQL_TEXT_FIELD_LIMIT
      raise StandardError.new("Maximum allowed workflow inputs is #{WORKFLOW_DISPATCH_INPUT_LIMIT}") if workflow_inputs.size > WORKFLOW_DISPATCH_INPUT_LIMIT
    end

    def map_inputs(parsed_workflow, workflow_input_keys, inputs_hash)
      workflow_inputs = {}
      stack_inputs_hash = inputs_hash["stack_inputs_hash"]
      workflow_input_keys.each do |key|
        if stack_inputs_hash[key].present? && !stack_inputs_hash[key]["is-secret"]
          workflow_inputs[key] = stack_inputs_hash[key]["value"].to_s
        end
      end

      validate_limits(workflow_inputs)
      # Patches default inputs defined in the workflow
      # Raises exception if a required input is not provided
      parsed_workflow.process_inputs(workflow_inputs)
    end

    def dispatch_workflow(repo, actor, inputs_hash)
      workflow_path = ".github/workflows/#{ inputs_hash["workflow_path"] }"
      parsed_workflow = WorkflowDispatchStep.get_parsed_workflow(repo, workflow_path, repo.default_branch.b)
      workflow_input_keys = get_workflow_input_keys(parsed_workflow)
      workflow_inputs = map_inputs(parsed_workflow, workflow_input_keys, inputs_hash)
      # Install launch app if it is not installed
      # This is an attempt to mitigate flakiness during workflow dispatch
      # https://github.com/github/github-stacks/issues/290
      unless repo.actions_app_installed?
        repo.enable_actions_app(
          actor: actor,
          entry_point: :step_stacks_dispatch_workflow_enable_actions_app
        )
      end
      repo.dispatch_workflow_event(actor.id, workflow_path, repo.default_branch.b, workflow_inputs)
    end
  end
end
