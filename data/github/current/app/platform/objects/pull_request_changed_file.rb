# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestChangedFile < Platform::Objects::Base
      description "A file changed in a pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, file)
        permission.async_repo_and_org_owner(file).then do |repo, org|
          permission.access_allowed?(:list_pull_request_files, resource: file.pull_request, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end


      scopeless_tokens_as_minimum

      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      field :path, String, description: "The path of the file.", null: false

      def path
        GitHub::Encoding.try_guess_and_transcode(object.path)
      end

      field :viewer_viewed_state, Enums::FileViewedState, description: "The state of the file for the viewer.", null: false

      def viewer_viewed_state
        user_reviewed_files = object.pull_request.user_reviewed_files_for(@context[:viewer])
        if user_reviewed_files.reviewed?(object.path)
          :viewed
        elsif user_reviewed_files.dismissed?(object.path)
          :dismissed
        else
          :unviewed
        end
      end

      field :change_type, Enums::PatchStatus, description: "How the file was changed in this PullRequest", null: false
      def change_type
        @object.status == "removed" ? :deleted : @object.status.to_sym
      end

      field :additions, Integer, description: "The number of additions to the file.", null: false
      field :deletions, Integer, description: "The number of deletions to the file.", null: false
      field :path_digest, String, "The hashed path of the changed file", null: false, visibility: :internal
    end
  end
end
