# typed: false
# frozen_string_literal: true

module StacksSteps
  class CleanupStep < Step
    def self.validate_inputs(inputs_hash, repo:, actor:, stack_repo: nil)
    end

    def weight
      @weight ||= StacksSteps::WeightMap::ONE_EIGHTY_SECOND
    end

    def self.get_step_name
      "CleanupStep"
    end

    def get_step_group
      StepGroup.stack_cleanup
    end

    def run(repo:, actor:)
      begin
        steps_in_plan = self.plan.stacks_step.fetch_steps_for_plan(self.instance_id)
        cleanedup_steps = []
        steps_in_plan.each do |step|
          next if cleanedup_steps.include?(step[:type])
          step.cleanup(repo: repo, actor: actor)

          cleanedup_steps.push(step[:type])
        end
      rescue StandardError => e # rubocop:todo Lint/RescueException
        GitHub::Logger.log_exception(
          { fn: "#{self.class.name}##{__method__}", repo_id: repo.id }, e)
        raise Errors::CleanupStepError.new(e.message)
      end
    end

    def cleanup(repo:, actor:)
    end
  end
end
