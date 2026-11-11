# typed: true
# frozen_string_literal: true

module CopilotIssues
  module Errors
    DOMAIN_SERVICE_ERRORS = T.let([
      GH::Result::Error::NotFound,
      GH::Result::Error::LockedForRebalance,
      GH::Result::Error::ServiceRateLimited,
      GH::Result::Error::NotSaved,
    ], T::Array[T.class_of(GH::Result::Error)])

    ADD_SUB_ISSUE_VALIDATION_ERRORS = T.let([
      "may only be an issue",
      "cannot have more than #{SubIssue::MAXIMUM_BREADTH} sub-issues",
      "cannot be the same as the parent issue",
      "may only have one parent",
      "may not create a circular dependency",
      "may not contain duplicate sub-issues",
      "transfer is in-progress",
      "#{SubIssue::MAXIMUM_HEIGHT_MESSAGE}"
    ], T::Array[String]).freeze

    class ContinuableError < StandardError
      extend T::Helpers
      abstract!

      sig { returns(T::Array[String]) }
      attr_reader :errors

      sig { returns(String) }
      attr_reader :type

      sig { abstract.returns(T::Hash[String, T.untyped]) }
      def log_tags; end
    end

    class AgentAssignmentError < ContinuableError
      sig { params(issue_url: String, repository: String, errors: T::Array[String]).void }
      def initialize(issue_url, repository, errors)
        super("Failed to assign copilot to issue: #{issue_url}")
        @issue_url = issue_url
        @repository = repository
        @errors = errors
        @type = "copilot_assignment"
      end

      sig { returns(String) }
      attr_reader :issue_url

      sig { returns(String) }
      attr_reader :repository

      sig { override.returns(T::Hash[String, T.untyped]) }
      def log_tags
        {
          "gh.issue_url" => @issue_url,
          "gh.domain.errors" => @errors,
          "gh.error_type" => @type,
        }
      end
    end

    class ProjectAssignmentError < ContinuableError
      sig { params(project: String, errors: T::Array[String]).void }
      def initialize(project, errors)
        super("Failed to assign project: #{project}")
        @project = project
        @errors = errors
        @type = "project"
      end

      sig { returns(String) }
      attr_reader :project

      sig { override.returns(T::Hash[String, T.untyped]) }
      def log_tags
        {
          "gh.project_title" => @project,
          "gh.domain.errors" => @errors,
          "gh.error_type" => @type,
        }
      end
    end

    class DependencyAssignmentError < ContinuableError
      sig { params(blocking_issue_tag: String, errors: T::Array[String]).void }
      def initialize(blocking_issue_tag, errors)
        super("Failed to add dependency: #{blocking_issue_tag}")
        @blocking_issue_tag = blocking_issue_tag
        @errors = errors
        @type = "dependency"
      end

      sig { returns(String) }
      attr_reader :blocking_issue_tag

      sig { override.returns(T::Hash[String, T.untyped]) }
      def log_tags
        {
          "gh.blocking_issue_tag" => @blocking_issue_tag,
          "gh.domain.errors" => @errors,
          "gh.error_type" => @type,
        }
      end
    end

    class TemplateParsingError < ContinuableError
      sig { params(template_filename: String, errors: T::Array[String]).void }
      def initialize(template_filename, errors)
        super("Failed to parse template: #{template_filename}")
        @template_filename = template_filename
        @errors = errors
        @type = "template_parsing"
      end

      sig { returns(String) }
      attr_reader :template_filename

      sig { override.returns(T::Hash[String, T.untyped]) }
      def log_tags
        {
          "gh.template_filename" => @template_filename,
          "gh.domain.errors" => @errors,
          "gh.error_type" => @type,
        }
      end
    end

    class IssueCreationError < StandardError
      extend T::Helpers
      abstract!

      sig { returns(T.nilable(Integer)) }
      attr_reader :repository_id

      sig { returns(T.nilable(String)) }
      attr_reader :issue_tag

      sig { returns(String) }
      attr_reader :type

      sig { abstract.returns(T::Hash[String, T.untyped]) }
      def log_tags; end
    end

    class ValidationOrAccessError < IssueCreationError
      sig { params(message: String, repository_id: T.nilable(Integer), issue_tag: T.nilable(String)).void }
      def initialize(message, repository_id: nil, issue_tag: nil)
        super(message)
        @repository_id = repository_id
        @issue_tag = issue_tag
        @type = "validation_or_access"
      end

      sig { override.returns(T::Hash[String, T.untyped]) }
      def log_tags
        {
          "gh.repository_id" => @repository_id,
          "gh.issue_tag" => @issue_tag,
          "gh.error_type" => @type,
        }
      end
    end

    class ServiceError < IssueCreationError
      sig { params(message: String, repository_id: T.nilable(Integer), issue_tag: T.nilable(String)).void }
      def initialize(message, repository_id: nil, issue_tag: nil)
        super(message)
        @repository_id = repository_id
        @issue_tag = issue_tag
        @type = "service"
      end

      sig { override.returns(T::Hash[String, T.untyped]) }
      def log_tags
        {
          "gh.repository_id" => @repository_id,
          "gh.issue_tag" => @issue_tag,
          "gh.error_type" => @type,
        }
      end
    end

    module ErrorParser
      sig { params(errors: T::Array[T::Hash[String, T.untyped]], action_message: String, repository_id: Integer, issue_tag: T.nilable(String)).returns(IssueCreationError) }
      def self.parse_graphql_error(errors, action_message, repository_id, issue_tag: nil)
        graphql_error_message = T.must(errors[0]).dig("message") || "Unknown error"
        if ADD_SUB_ISSUE_VALIDATION_ERRORS.any? { |msg| graphql_error_message.include?(msg) }
          ValidationOrAccessError.new(
            "#{action_message}. #{graphql_error_message}",
            repository_id:,
            issue_tag:,
          )
        else
          ServiceError.new(
            "#{action_message}. #{graphql_error_message}",
            repository_id:,
            issue_tag:,
          )
        end
      end

      sig { params(error: GH::Result::Error[T.untyped], action_message: String, repository_id: Integer, issue_tag: T.nilable(String)).returns(IssueCreationError) }
      def self.parse_domain_error(error, action_message, repository_id, issue_tag: nil)
        case error
        when *DOMAIN_SERVICE_ERRORS
          ServiceError.new(
            "#{action_message}. #{error.message}",
            repository_id:,
            issue_tag:,
          )
        else
          ValidationOrAccessError.new(
            "#{action_message}. #{error.message}",
            repository_id:,
            issue_tag:,
          )
        end
      end
    end
  end
end
