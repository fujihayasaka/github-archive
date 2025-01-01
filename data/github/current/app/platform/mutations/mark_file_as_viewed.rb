# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkFileAsViewed < Platform::Mutations::Base
      description "Mark a pull request file as viewed"

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, description: "The Node ID of the pull request.", required: true, loads: Objects::PullRequest
      argument :path, String, description: "The path of the file to mark as viewed", required: true

      field :pull_request, Objects::PullRequest, "The updated pull request.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed? :get_pull_request, repo: repo, current_org: org, resource: pull_request, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(pull_request:, **inputs)
        begin
          context[:viewer].reviewed_files.create!(
            filepath: inputs[:path],
            pull_request_id: pull_request.id,
            head_sha: pull_request.head_sha
          )
        rescue ActiveRecord::RecordNotUnique
          update_existing_record(pull_request, inputs[:path])
        rescue ActiveRecord::RecordInvalid => error
          if record_not_unique?(error)
            update_existing_record(pull_request, inputs[:path])
          else
            raise Errors::Unprocessable.new(error.record.errors.full_messages.join(", "))
          end
        end

        { pull_request: pull_request }
      end

      private

      sig { params(pull_request: PullRequest, filepath: String).void }
      def update_existing_record(pull_request, filepath)
        # race conditions with marking/unmarking a file as viewed can result in this record being deleted after we attempt the create.
        reviewed_file = context[:viewer].reviewed_files.for(pull_request).find_by(filepath:)
        raise Errors::Unprocessable.new("Failed to mark file as viewed") unless reviewed_file

        reviewed_file.update_attribute(:dismissed, false)
      end

      sig { params(error: ActiveRecord::RecordInvalid).returns(T::Boolean) }
      def record_not_unique?(error)
        error.record.errors.map(&:type).include?(:taken)
      end
    end
  end
end
