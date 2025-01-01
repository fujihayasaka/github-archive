# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class ViewerMayNotSee < Errors::Internal
      attr_reader :operation_name
      def initialize(application_object, graphql_object_defn, query_context, graphql_path)
        @operation_name = query_context.query.selected_operation_name || query_context.query.selected_operation.operation_type

        viewer = query_context[:viewer]
        viewer_s = if viewer.present?
          "#{viewer.display_login} (Node ID: #{viewer.global_relay_id})"
        else
          "nil"
        end

        message = <<~MSG
        A GraphQL resolver returned a `#{application_object.class.name}`, but
        `#{graphql_object_defn.name}.async_viewer_can_see?` returned `false` for it.

        The #{application_object.class.name} appeared in the query at:

            #{@operation_name} > #{graphql_path.join(" > ")}

        This means that the authorization check thinks that the object is _not_ permitted,
        but the resolver thought it _was permitted_.

        The unauthorized #{application_object.class.name} is:
          - Node ID: #{application_object.respond_to?(:global_relay_id) ? application_object.global_relay_id : "(none)"}
          - Database ID: #{application_object.respond_to?(:id) ? application_object.id : "(none)"}

        The viewer is: #{viewer_s}

        To address this issue:

        - Check the resolver: should it perform more filtering before returning?
        - Check the authorization method: should it have permitted this object?
        - Drop a link to this needle or CI failure in #graphql
        MSG

        super(message)
      end
    end
  end
end
