# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class RepositoriesContributedTo < Resolvers::Base
      argument :privacy, Enums::RepositoryPrivacy, "If non-null, filters repositories according to privacy", required: false

      argument :order_by, Inputs::RepositoryOrder, "Ordering options for repositories returned from the connection", required: false

      argument :is_locked, Boolean, "If non-null, filters repositories according to whether they have been locked", required: false

      argument :has_issues, Boolean, "If non-null, filters repositories according to whether they have issues enabled", required: false

      argument :include_user_repositories, Boolean, "If true, include user repositories", required: false

      argument :contribution_types, [Enums::RepositoryContributionType, null: true], "If non-null, include only the specified types of contributions. The GitHub.com UI uses [COMMIT, ISSUE, PULL_REQUEST, REPOSITORY]", required: false

      type Connections::Repository, null: false

      def resolve(**arguments)
        return Promise.resolve(ArrayWrapper.new([])) if object.private_profile_for?(context[:viewer])

        promise = if context[:viewer].is_a?(Bot)
          context[:viewer].installation.async_target
        else
          Promise.resolve(true)
        end

        promise.then do
          contributed_repositories = get_viewable_contributed_repositories(object, arguments, context)
          filter_repositories(contributed_repositories, object, arguments, context)
        end
      end

      def get_viewable_contributed_repositories(owner, arguments, context)
        collector = owner.contributions_collector(viewer: context[:viewer])

        requested_contribution_classes = arguments[:contribution_types] || collector.contribution_classes

        viewable_repositories = requested_contribution_classes.map do |klass|
          collector.visible_contributions_of(klass).map(&:repository)
        end.flatten

        ::Repository.where(id: viewable_repositories.map(&:id))
      end

      # Owner here is a user
      def filter_repositories(relation, owner, arguments, context)
        relation = relation.filter_spam_and_disabled_for(context[:viewer])

        case arguments[:is_locked]
        when true
          relation = relation.locked_repos
        when false
          relation = relation.unlocked_repos
        end

        filtering_on_private = arguments[:privacy] == "private"
        filtering_on_public = arguments[:privacy] == "public"

        if filtering_on_private
          if !context[:permission].async_can_list_private_repos?(owner).sync
            relation = ::Repository.none
          else
            relation = relation.private_scope
          end
        elsif filtering_on_public
          relation = relation.public_scope
        elsif !context[:permission].async_can_list_private_repos?(owner).sync
          relation = relation.public_scope
        end

        case arguments[:is_fork]
        when true
          relation = relation.where("repositories.parent_id IS NOT NULL")
        when false
          relation = relation.where("repositories.parent_id IS NULL")
        end
        case arguments[:has_issues]
        when true
          relation = relation.where("repositories.has_issues=TRUE")
        when false
          relation = relation.where("repositories.has_issues=FALSE")
        end

        if arguments[:order_by]
          relation = relation.order(arguments[:order_by][:field] => arguments[:order_by][:direction])
        end

        unless arguments[:include_user_repositories]
          relation = relation.where("repositories.owner_id != ?", owner.id)
        end

        relation.active
        # To keep the validation for first and pagination intact
        authorized_repos = context[:cap_filter].authorized_resource_ids(relation)
        ::Repository.where(id: authorized_repos)

      end
    end
  end
end
