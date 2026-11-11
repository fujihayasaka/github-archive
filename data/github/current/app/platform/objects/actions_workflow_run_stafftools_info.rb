# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ActionsWorkflowRunStafftoolsInfo < Platform::Objects::Base
      description "A common reputation type for Spamurai."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      # Example https://github.com/hajikakanama/lana/actions/runs/506200531
      field :permalink, String, "Link to actions workflow run.", null: false
      def permalink
        Loaders::ActiveRecordAssociation.load(@object, :check_suite).then do |cs|
          Loaders::ActiveRecordAssociation.load(cs, :repository).then do |r|
            Loaders::ActiveRecordAssociation.load(r, :network).then do
              @object.permalink
            end
          end
        end
      end

      # Example https://github.com/hajikakanama/lana/blob/f92fb13199cc5efb66fa7559288febff390489ec/.github/workflows/blank.yml
      field :workflow_file_link, String, "Link to workflow file for run.", null: false
      def workflow_file_link
        Loaders::ActiveRecordAssociation.load(@object, :check_suite).then do |cs|
          Loaders::ActiveRecordAssociation.load(cs, :repository).then do |r|
            Loaders::ActiveRecordAssociation.load(r, :network).then do
              @object.workflow_file_link
            end
          end
        end
      end

      # Example f92fb13199cc5efb66fa7559288febff390489ec
      field :commit_oid, String, "Commit oid of code used for workflow run.", null: true
      def commit_oid
        Loaders::ActiveRecordAssociation.load(@object, :check_suite).then do |cs|
          Loaders::ActiveRecordAssociation.load(cs, :repository).then do |r|
            Loaders::ActiveRecordAssociation.load(r, :network).then do
              @object.commit_oid
            end
          end
        end
      end

      # Example "Create blank.yml"
      field :title, String, "Title of workflow run.", null: false
      def title
        Loaders::ActiveRecordAssociation.load(@object, :check_suite).then do
          @object.async_workflow.then do
            @object.title
          end
        end
      end

      # Example "CI"
      field :workflow_name, String, "Name of workflow.", null: false
      def workflow_name
        @object.async_workflow.then do
          @object.workflow_name
        end
      end

      # Example 1
      field :run_number, Integer, "Number of run.", null: false
    end
  end
end
