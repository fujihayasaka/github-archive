# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module RequirableByPullRequest
      extend T::Helpers

      requires_ancestor { GraphQL::Schema::Object }

      include Platform::Interfaces::Base
      description "Represents a type that can be required by a pull request for merging."

      field :is_required, Boolean, description: "Whether this is required to pass before merging for a specific pull request.", null: false do
        argument :pull_request_id, ID, "The id of the pull request this is required for", required: false
        argument :pull_request_number, Integer, "The number of the pull request this is required for", required: false
      end

      def is_required(**arguments)
        if arguments[:pull_request_id]
          Platform::Helpers::NodeIdentification.async_typed_object_from_id([Objects::PullRequest], arguments[:pull_request_id], context).then do |pull|
            pull.async_base_repository.then do
              @object.async_required_for_pull_request?(pull)
            end
          end
        elsif arguments[:pull_request_number]
          @object.async_repository.then do |repo|
            Loaders::IssueishByNumber.load(repo.id, arguments[:pull_request_number]).then do |issueish|
              unless issueish && issueish.is_a?(PullRequest)
                raise Platform::Errors::NotFound, "Could not resolve to a pull request with the number of '#{arguments[:pull_request_number]}'"
              end
              issueish.async_base_repository.then do
                @object.async_required_for_pull_request?(issueish)
              end
            end
          end
        else
          raise Platform::Errors::Unprocessable.new("A pull request ID or pull request number is required.")
        end
      end
    end
  end
end
