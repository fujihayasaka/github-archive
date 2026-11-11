# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    class ResourceType < T::Enum

      enums do
        Codespace       = new("codespace")
        Business        = new("business")
        Organization    = new("organization")
        PackageRegistry = new("package")
        ProtectedBranch = new("protected_branch")
        PullRequest     = new("pull_request")
        Repository      = new("repository")
        WorkflowRun     = new("workflow_run")
        User            = new("user")
      end

      sig { params(resource: T.any(String, ResourceType, Object)).returns(ResourceType) }
      def self.for(resource)
        return resource if resource.is_a?(ResourceType)

        name = case resource
        when String
          resource
        else
          T.must(resource.class.name)
        end

        deserialize(name.underscore.downcase)
      end

      sig { params(subject_type: String).returns(T.nilable(ResourceType)) }
      def self.from_subject_type(subject_type)
        # User/repositories/metadata => User/repositories
        ability_type_prefix = T.must(subject_type.split("/")[0..-2]).join("/")
        resource = T.must(ability_type_prefix.split("/").last).singularize.underscore

        deserialize(resource)
      end
    end
  end
end
