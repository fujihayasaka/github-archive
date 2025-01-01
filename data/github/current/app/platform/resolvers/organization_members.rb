# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class OrganizationMembers < Platform::Resolvers::Users
      type Connections::OrganizationMember, null: false

      def resolve(**arguments)
        max_members_limit = arguments[:max_members_limit].nil? ? ::Organization::MEGA_ORG_MEMBER_THRESHOLD : arguments[:max_members_limit]
        if context[:permission].can_list_private_org_members?(object)
          user_ids = object.visible_user_ids_for(context[:viewer], limit: max_members_limit)
        else
          user_ids = object.public_member_ids.take(max_members_limit)
        end

        # Context: This was put in place to solve an issue where
        # Intel was experiencing a timeout when querying for org members.
        #
        # This could probably be expanded to be more general solution eventually, since
        # they aren't the only ones that have had this issue (here's looking at you, Epic Games).
        #
        # TODO add some logic to handle before cursor and the last argument.
        #
        # https://github.zendesk.com/agent/tickets/1526155
        #
        if GitHub.flipper[:limit_user_ids_in_org_member_query].enabled?(context[:viewer]) && context[:current_arguments].key?(:first)
          if context[:current_arguments].key?(:after) && !context[:current_arguments][:after].nil?
            cursor_id = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(context[:current_arguments][:after])

            # sort the user_ids array and then get all the ids after the cursor_id up to the first argument
            if cursor_id.present? && cursor_id.first.is_a?(Integer)
              # Faking out the pagination system here:
              # 1. We include the current cursor_id in the user_ids array (id < cursor_id) so that it will
              # correctly determine the value of the hasPreviousPage field.
              # 2. The + 2 will overpopulate the user_ids array. This will allow for enough results
              # to be overfetched from the database so that the hasNextPage field will be accurate.
              user_ids = user_ids.sort.drop_while { |id| id < cursor_id.first }.take(context[:current_arguments][:first] + 2)
            end
          else
            # just grab the first from the sorted user_ids array.
            user_ids = user_ids.sort.take(context[:current_arguments][:first] + 2)
          end
        end

        users = if user_ids.empty?
          User.none
        else
          User.where(ActiveRecord::Base.sanitize_sql(["users.id IN (?)", user_ids]))
        end

        filter_spam(users)
      end
    end
  end
end
