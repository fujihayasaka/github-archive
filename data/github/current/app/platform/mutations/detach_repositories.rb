# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DetachRepositories < Platform::Mutations::Base
      description "Disconnect repositories from their network"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :repository_ids, [ID], "The global relay ids of repositories to detach.", required: true, loads: Objects::Repository, as: :repositories
      argument :async, Boolean, "Perform action in backgroun job", required: false, default_value: false

      field :success, [Objects::Repository], "The detached repositories.", null: true
      field :failure, [Objects::Repository], "The repositories that failed to detach", null: true

      def resolve(repositories:, **inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to detach repositories."
        end

        success = []
        failure = []
        repositories.each do |repository|
          begin
            if inputs[:async]
              repository.detach!(synchronous: false)
            else
              repository.detach!(synchronous: true)
            end
          rescue RepositoryNetwork::UnsafeExtractionError, Repository::NetworkDependency::DetachFailure => e
            failure.push(repository)
            Failbot.report(e, repo_id: repository.id)
          else
            success.push(repository)
          end
        end

        { success: success, failure: failure }
      end
    end
  end
end
