# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class RepositoryDeployments < Resolvers::Deployments
      def resolve(**arguments)
        context[:permission].async_can_list_deployments?(repo: object).then do |can_list_deployments|
          return ::Deployment.none unless can_list_deployments

          query = @object.deployments

          # Filter by environments
          env_filters = nil
          if arguments[:filter_by] && arguments[:filter_by][:environments] && arguments[:filter_by][:environments].any?
            env_filters = arguments[:filter_by][:environments]
          elsif arguments[:environments] && arguments[:environments].any?
            env_filters = arguments[:environments]
          elsif arguments[:filter_by] && arguments[:filter_by][:environment]
            env_filters = arguments[:filter_by][:environment]
          end
          if env_filters
            query = query.where(latest_environment: env_filters)
          end

          # Filter by states
          state_filters = nil
          if arguments[:filter_by] && arguments[:filter_by][:states] && arguments[:filter_by][:states].any?
            state_filters = arguments[:filter_by][:states]
          elsif arguments[:filter_by] && arguments[:filter_by][:state]
            state_filters = arguments[:filter_by][:state]
          end

          if state_filters
            if state_filters.include?("pending")
              # also include deployments that not in DeploymentStatus table
              state_filters << nil
            end
            query = query.where(latest_status_state: state_filters)
          end

          # Filter by creators
          creator_filters = nil
          if arguments[:filter_by] && arguments[:filter_by][:creators] && arguments[:filter_by][:creators].any?
            creator_filters = arguments[:filter_by][:creators]
          elsif arguments[:filter_by] && arguments[:filter_by][:creator]
            creator_filters = arguments[:filter_by][:creator]
          end
          if creator_filters
            user_ids = User.where(login: creator_filters).pluck(:id)
            # Bail on the query if there are no corresponding users
            return query.none unless user_ids.any?

            query = query.where(creator_id: user_ids)
          end

          # Filter by branches/tags
          ref_filters = nil
          if arguments[:filter_by] && arguments[:filter_by][:refs] && arguments[:filter_by][:refs].any?
            ref_filters = arguments[:filter_by][:refs]
          elsif arguments[:filter_by] && arguments[:filter_by][:ref]
            ref_filters = arguments[:filter_by][:ref]
          end
          if ref_filters
            query = query.where(ref: ref_filters)
          end

          # Filter by commits
          if arguments[:filter_by] && arguments[:filter_by][:sha]
            query = query.where(sha: arguments[:filter_by][:sha])
          end

          # Filter by dates
          if arguments[:filter_by]
            # Possibly shouldn't support both of these being used together? Not invalid, though....
            if arguments[:filter_by][:created_at]
              query = query.where("deployments.created_at >= ?", arguments[:filter_by][:created_at])
            end
            if arguments[:filter_by][:updated_at]
              query = query.where("deployments.updated_at >= ?", arguments[:filter_by][:updated_at])
            end
          end

          # Finally, control the sort order
          field = arguments[:order_by][:field]
          direction = arguments[:order_by][:direction]
          ordering = "deployments.#{field} #{direction}"
          query.reorder(ordering)
        end
      end
    end
  end
end
