# typed: true
# frozen_string_literal: true

module StacksSteps
  class RepoMetadataStep < Step
    def self.validate_inputs(inputs_hash, repo:, actor:, stack_repo: nil)
      method_name = "#{self.class.name}##{__method__}"
      if (authorization = ContentAuthorizer.authorize(actor, :repo, :update, { repo: repo })).failed?
        GitHub::Logger.log(fn: method_name,
          message: "User not authorized to update")
        raise Errors::ContentAuthorizerError.new(authorization.error_messages)
      end

      if inputs_hash.has_key?("topics")
        topic_names = inputs_hash["topics"]
        invalid_names = topic_names.reject { |name| Topic.valid_name?(name) }
        if invalid_names.any?
          GitHub::Logger.log(fn: method_name, message: "Invalid topic names")
          raise Errors::InvalidInputError.new("topics", "Value must start with a lowercase letter or number, consist of #{Topic::MAX_NAME_LENGTH} characters or less and can include hyphens.")
        end
      end
    end

    def self.get_step_name
      "RepoMetadataStep"
    end

    def get_step_group
      StepGroup.repo_config
    end

    def run(repo:, actor:)
      method_name = "#{self.class.name}##{__method__}"
      inputs_hash = self.inputs


      if inputs_hash.has_key?("description")
        repo.send("description=", inputs_hash["description"])
        unless repo.save
          GitHub::Logger.error(fn: method_name,
            message: "Failed to update repo description", repo_id: repo.id)
          raise Errors::RepoMetadataUpdateError.new("description")
        end
      end

      if inputs_hash.has_key?("topics")
        unless repo.update_topics(inputs_hash["topics"], user: actor)
          GitHub::Logger.error(fn: method_name,
            message: "Failed to update topics", repo_id: repo.id)
          raise Errors::RepoMetadataUpdateError.new("topics")
        end
      end
    end

    def cleanup(repo:, actor:)
    end
  end
end
