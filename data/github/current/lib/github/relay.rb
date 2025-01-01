# typed: false
# frozen_string_literal: true

# This file has some type annotations in sorbet/rbi/shims/relay.rbi

module GitHub
  module Relay
    module TypeName
      def platform_type_name
        class_name = self.class.name
        if i = class_name.rindex("::")
          class_name[(i + 2)..-1]
        else
          class_name
        end
      end
    end

    # Meant to be mixed into classes that represent our GraphQL types. Usually,
    # ActiveRecord::Base classes.
    module GlobalIdentification
      include TypeName

      def legacy_global_id
        if pull_request_loaded_as_issue?
          ::Platform::Helpers::NodeIdentification.to_legacy_global_id("PullRequest", pull_request_id)
        elsif self.class.name == "DiscussionReaction"
          ::Platform::Helpers::NodeIdentification.to_legacy_global_id("DiscussionReaction", global_id)
        elsif self.class.name == "DiscussionCommentReaction"
          ::Platform::Helpers::NodeIdentification.to_legacy_global_id("DiscussionCommentReaction", global_id)
        else
          ::Platform::Helpers::NodeIdentification.to_legacy_global_id(platform_type_name, global_id)
        end
      end

      def global_id
        id
      end

      def next_global_id
        Platform::Helpers::NodeIdentification.async_to_next_global_id(self).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      module RequireBatchLoadingForNextGlobalId
        # In test, raise an error if this hook makes any unbatched association loads.
        # (The problem is, integration tests might pass because the object was already
        # cached during the graphql query. So this increases our test coverage of this method.)
        def next_global_id
          Platform::QueryTracker.tracking_association_loads(path: [self.class.name, "next_global_id"]) { super }
        end
      end

      def self.included(child_class)
        if GitHub::AppEnvironment.test?
          child_class.prepend RequireBatchLoadingForNextGlobalId
        end
      end

      # @return [String] Using this platform type's "ready date", choose between {#next_global_id} and {#global_relay_id}
      #   This method also returns legacy IDs for GitHub Enterprise (since ready dates don't apply there)
      #   and if the feature flag is turned off.
      def global_relay_id #rubocop: disable GitHub/UntypedObjectId
        type_name = pull_request_loaded_as_issue? ? "PullRequest" : platform_type_name
        type_name = "Reaction" if Platform::Helpers::NodeIdentification::REACTION_TYPES.include?(platform_type_name)
        type_definition = Platform::Schema.get_type(type_name)
        if !GitHub.enterprise? &&
            type_definition &&
            type_definition.kind.object? &&
            type_definition.use_next_id?(self)
          next_global_id
        else
          legacy_global_id
        end
      end

      private

      # When a pull request is created a row in the issues table is created as
      # well as a row in the pull_requests table.  The row created in the
      # issues table has the foreign key to the pull request stored in the
      # pull_request_id column.  When looking up an "issue" of this kind, we
      # really just want the pull request.  Therefore, this logic will return
      # the global id for the row in the pull_requests table instead.
      def pull_request_loaded_as_issue?
        platform_type_name == "Issue" && pull_request_id.present?
      end
    end
  end
end
