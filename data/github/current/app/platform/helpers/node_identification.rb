# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module NodeIdentification
      REACTION_TYPES = %w(
        CommitCommentReaction
        DiscussionReaction
        DiscussionCommentReaction
        DiscussionPostReaction
        DiscussionPostReplyReaction
        IssueReaction
        IssueCommentReaction
        PullRequestReviewReaction
        PullRequestReviewCommentReaction
        ReleaseReaction
        RepositoryAdvisoryReaction
        RepositoryAdvisoryCommentReaction
      )

      def self.type_name_from_object(object)
        return "Reaction" if REACTION_TYPES.include?(object.platform_type_name)
        return "EnterpriseMemberInvitation" if object.platform_type_name == "EnterpriseAdministratorInvitation" && object.unaffiliated?
        object.platform_type_name
      end

      def self.type_from_object(object)
        # We're trying to move global ID generation as an ObjectType concern.
        # In the mean time, we use this as a bridge.
        return Platform::Schema.get_type("Reaction") if REACTION_TYPES.include?(object.platform_type_name)
        return Platform::Schema.get_type("EnterpriseMemberInvitation") if object.platform_type_name == "EnterpriseAdministratorInvitation" && object.unaffiliated?

        Platform::Schema.get_type(object.platform_type_name)
      end

      def self.from_global_id(global_id)
        raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of 'nil'." if global_id.nil?
        parsed = GlobalId.parse(global_id)

        [parsed.type, parsed.id]
      end

      # TODO: Remove this method once all the calls to it have been removed.
      def self.to_global_id(type_name, id)
        to_legacy_global_id(type_name, id)
      end

      def self.to_legacy_global_id(type_name, id)
        Base64.strict_encode64(["0", type_name.length, ":", type_name, id.to_s].join)
      end

      def self.async_to_next_global_id(object, type = nil)
        object_type = Platform::Schema.get_type(type&.to_s) if object.respond_to?(:platform_type_name=)
        object_type ||= type_from_object(object)

        if object_type.nil?
          e = ArgumentError.new("Object #{object} can not be mapped to a GraphQL Object Type. Set a valid `platform_type_name`")
          Failbot.report!(e)
          raise e # rubocop:disable GitHub/UsePlatformErrors
        end

        if object_type.graphql_name == "Issue" && object.pull_request_id.present?
          # This issue is shown to users as a pull request, but has been loaded as an issue.
          # Return the ID for the pull request that it _really_ is
          object.async_pull_request.then do |pr|
            # In the case where the parent pull request has been deleted, just show the object ID instead.
            if pr.nil?
              object_type.async_global_id(object)
            else
              Platform::Objects::PullRequest.async_global_id(pr)
            end
          end
        else
          object_type.async_global_id(object)
        end
      end

      # Warning! This method might return _anything_.
      # If a user reverse-engineers a gid, they might fetch any object.
      # Prefer `typed_object_from_id` when you want an object of a certain type.
      def self.untyped_object_from_id(gid, permission:, target: :internal)
        raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of 'nil'." if gid.nil?
        parsed = GlobalId.parse(gid)

        if REACTION_TYPES.include?(parsed.type)
          type = Platform::Schema.get_type("Reaction")
          return Promise.resolve(nil) unless type

          id_promise = if parsed.is_a?(GlobalId::Next)
            type.load_from_next_global_id(parsed)
          else
            Platform::Objects.async_find_record_by_id(parsed.type.constantize, parsed.id)
          end
        else
          type = Platform::Schema.get_type(parsed.type)
          return Promise.resolve(nil) unless type

          if !type.visibility.include?(target)
            raise Errors::NotFound, "Could not resolve to a node with the global id of '#{gid}'."
          end

          id_promise = if parsed.is_a?(GlobalId::Next)
            type.load_from_next_global_id(parsed)
          else
            type.load_from_global_id(parsed.id)
          end
        end

        id_promise.then do |object|
          type_name = if object.is_a?(::PullRequest) && parsed.type == "Issue"
            # Support a special case: `Objects.async_find_record_by_id`
            # will return a PullRequest when the `id` loads an Issue
            # which is actually a pull request. In that case,
            # we should update our type info accordingly.
            "PullRequest"
          elsif object.is_a?(::Audit::Elastic::Hit)
            "AuditLog::#{parsed.type}"
          elsif REACTION_TYPES.include?(parsed.type)
            "Reaction"
          else
            parsed.type
          end

          if object
            is_gist_comment = object.is_a?(::UserContentEdit) && object.user_content_type == "GistComment"
            is_non_gist_prefix = parsed.is_a?(GlobalId::Next) && parsed.parts[:prefix] != :rgce
            if  is_gist_comment && is_non_gist_prefix
              # Since GistComments are not backed by abilities, they are not
              # filtered out by the type checks below, so we need to manually filter them out here. We should
              # only return a GistComment if the prefix is :rgce, since for that prefix we ensure the user has
              # both the id of the GistComment, and the Gist itself. See https://github.com/github/repos/issues/3068
              raise Errors::NotFound, "Could not resolve to a node with the global id of '#{gid}'."
            end

            # Here we need to check if the parsed prefix is equal to user_content_type on the object for gists
            permission.typed_can_access?(type_name, object).then do |accessible|
              if accessible
                permission.typed_can_see?(type_name, object).then do |readable|
                  if readable
                    # We don't want to load spammy users by ID directly, although
                    # they _may_ be loaded in some contexts!
                    if type_name != "User" || !object.hide_from_user?(permission.viewer)
                      object
                    else
                      raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of '#{gid}'."
                    end
                  else # wasn't readable
                    raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of '#{gid}'."
                  end
                end
              else # didn't have the right API access
                raise Errors::NotFound, "Could not resolve to a node with the global id of '#{gid}'."
              end
            end
          else # didn't find it with the given global ID
            raise Errors::NotFound, "Could not resolve to a node with the global id of '#{gid}'."
          end
        end
      end

      # Load an object from `gid`, then assert that it is one of `possible_types`
      def self.typed_object_from_id(possible_types, gid, context)
        async_typed_object_from_id(possible_types, gid, context).sync
      end

      # A promise of `typed_object_from_id`
      def self.async_typed_object_from_id(possible_types, gid, context)
        raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of 'nil'." if gid.nil?
        Platform::Schema.object_from_id(gid, context).then do |object|
          type_name = type_name_from_object(object)
          actual_type = Platform::Schema.get_type(type_name)
          # Normalize old-style defns and new-style defns
          possible_types = Array(possible_types)

          if possible_types.any? { |type| type == actual_type || actual_type.interfaces.include?(type) }
            object
          else
            if context[:target] != :internal
              possible_types = possible_types.reject { |t| t.visibility == :internal }
            end
            type_phrase = possible_types.map(&:graphql_name).to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
            raise Errors::NotFound, "Could not resolve to #{type_phrase} node with the global id of '#{gid}'"
          end
        end
      end
    end
  end
end
