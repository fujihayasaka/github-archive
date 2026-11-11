# typed: true
# frozen_string_literal: true

module Errors
  STEP_EXECUTE_ERROR = "Step execution failed:"
  STEP_VALIDATION_ERROR = "Step validation failed:"
  STACK_INSTANCE_VALIDATION_ERROR = "Stack instance validation failed:"
  STACK_INSTANCE_RUN_TIME_ERROR = "Stack instance run time error:"
  STACK_INSTANCE_CLEANUP_ERROR = "Stack instance cleanup failed:"

  # Step Validation errors
  class MissingKeyError < StandardError
    def initialize(missing_key)
      super("#{STEP_VALIDATION_ERROR} '#{missing_key}' key missing in inputs")
    end
  end

  class ValidationError < StandardError
    def initialize(message)
      super("#{STEP_VALIDATION_ERROR} #{message}")
    end
  end

  class InvalidInputError < StandardError
    def initialize(key, message)
      super("#{STEP_VALIDATION_ERROR} Invalid value of #{key}. #{message}")
    end
  end

  class UserNotFound < StandardError
    def initialize(user_login)
      super("#{STEP_VALIDATION_ERROR} Could not find user '#{user_login}'")
    end
  end

  class RepositoryNotFound < StandardError
    def initialize(repository)
      super("#{STEP_VALIDATION_ERROR} Could not find specified repository #{repository}")
    end
  end

  class StepInvalidWeightError < StandardError
    def initialize(key)
      super("Invalid weight for step #{key}")
    end
  end

  # WorkflowDispatchStep errors
  class WorkflowDispatchError < StandardError
    def initialize(message)
      super("#{STEP_EXECUTE_ERROR} Error while triggering workflow dispatch. Error message: #{message}")
    end
  end

  # RepoMetadataStep errors
  class ContentAuthorizerError < StandardError
    def initialize(message)
      super("#{STEP_VALIDATION_ERROR} User unauthorized to update repo. #{message}")
    end
  end

  class RepoMetadataUpdateError < StandardError
    def initialize(key)
      super("#{STEP_EXECUTE_ERROR} Unable to update repository #{key}.")
    end
  end

  # RepoCloneStep errors
  class RepoCloningError < StandardError
    def initialize(message)
      super("#{STEP_EXECUTE_ERROR} #{message}")
    end
  end

  # SecuritySettingsStep Errors
  class SecurityParameterError < StandardError
    def initialize(key, message)
      super("#{STEP_VALIDATION_ERROR} Cannot enable #{key}. #{message}")
    end
  end

  class SecuritySettingsError < StandardError
    def initialize(key)
      super("#{STEP_EXECUTE_ERROR} Could not enable #{key}.")
    end
  end

  # BranchProtectionStep Errors
  class BranchProtectionParameterError < StandardError
    def initialize(name, key, message)
      super("#{STEP_VALIDATION_ERROR} Cannot enable #{key} in the branch #{name}. #{message}")
    end
  end

  class BranchProtectionError < StandardError
    def initialize(message)
      super("#{STEP_EXECUTE_ERROR} Error configuring branch protection. Error message: #{message}")
    end
  end

  # CreateEnvironmentStep Errors

  class CreateEnvironmentStepError < StandardError
    def initialize(message)
      super("#{STEP_EXECUTE_ERROR} Error occurred while creating environment. #{message}")
    end
  end

  #StacksCloneHelper Errors
  class CloneError < StandardError
    attr_accessor :error_reason_code

    def initialize(message, error_reason_code = nil)
      super("Could not finish repository cloning. #{message}")
      @error_reason_code = error_reason_code
    end
  end

  # StacksInstance Errors
  class StacksInstanceValidationError < StandardError
    def initialize(message)
      super("#{STACK_INSTANCE_VALIDATION_ERROR} #{message}")
    end
  end

  class StacksInstanceNotFoundError < StandardError
    def initialize(message)
      super("#{STACK_INSTANCE_RUN_TIME_ERROR} #{message}")
    end
  end

  class StacksInstanceAlreadyRunningError < StandardError
    def initialize(message)
      super("#{STACK_INSTANCE_RUN_TIME_ERROR} #{message}")
    end
  end

  class StacksInstanceRunTimeError < StandardError
    def initialize(message)
      super("#{STACK_INSTANCE_RUN_TIME_ERROR} #{message}")
    end
  end

  class StacksInstanceCleanupError < StandardError
    def initialize(message)
      super("#{STACK_INSTANCE_CLEANUP_ERROR} #{message}")
    end
  end

  class CleanupStepError < StandardError
    def initialize(message)
      super("#{STEP_EXECUTE_ERROR} #{message}")
    end
  end

  class StepError < StandardError; end

  class UnknownStepGroupError < StandardError; end

  class StacksParserError < StandardError
    def initialize(type, message)
      super("Stacks Parser Error [#{type}], #{message}.")
    end
  end

  class StacksPrePublishErrors < StandardError
    attr_accessor :other_data

    def initialize(message, other_data = nil)
      @other_data = other_data
      super(message)
    end
  end

  class StackUpdateError < StandardError; end
end
