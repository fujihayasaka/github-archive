# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class CommitDeployments < Resolvers::Deployments
      def resolve(**arguments)
        context[:permission].async_can_list_deployments?(repo: object.repository).then do |can_list_deployments|
          next ::Deployment.none unless can_list_deployments

          field = arguments[:order_by][:field]
          direction = arguments[:order_by][:direction]
          ordering = "deployments.#{field} #{direction}"

          object.async_repository.then do |repository|
            deployments = repository.deployments.by_sha(object.sha)
            if arguments[:environments] && arguments[:environments].any?
              deployments = deployments.where("latest_environment in (?)", arguments[:environments])
            end
            deployments.reorder(ordering)
          end
        end
      end
    end
  end
end
