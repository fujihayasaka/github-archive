# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class IssueType < Platform::Objects::Base
      docs_category :issues
      graphql_name "IssueType"
      scopeless_tokens_as_minimum

      description "Represents the type of Issue."

      implements_node templates: [[:it, :owner_id, :id]], as: "IT", ready_date: "1970-01-01" do |issue_type|
        {
          prefix: :it,
          owner_id: issue_type.owner_id,
          id: issue_type.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, issue_type: T.any(::IssueType, Platform::Models::IssueTypeWithContext)).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_api_can_access?(permission, issue_type)
        issue_type.async_owner.then do |owner|
          owner = T.cast(T.must(owner), ::Organization)
          next false unless owner.issue_types_enabled?

          repository = issue_type.repository if issue_type.is_a?(Platform::Models::IssueTypeWithContext)
          issue = issue_type.issue if issue_type.is_a?(Platform::Models::IssueTypeWithContext)

          # permission.access_allowed? will reject early, if the resource is not accessible by the viewer, i.e.
          # an anonymous viewer trying to access an organization. However, we need to account for scenarios where
          # we are viewing issue types in the context of an issue and/or repository, where anonymous access is allowed.
          resource = issue || repository || owner

          permission.access_allowed?(
            :read_issue_types,
            resource:,
            issue_type: issue_type,
            current_org: owner,
            current_repo: repository,
            current_issue: issue,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, issue_type: T.any(::IssueType, Platform::Models::IssueTypeWithContext)).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_viewer_can_see?(permission, issue_type)
        issue_type.async_owner.then do |owner|
          owner = T.cast(T.must(owner), ::Organization)
          next false unless owner.issue_types_enabled?
          # In the context of a repository, i.e. listing all issue types available for
          # a repository, the viewer must be able to access that repository. In the context of an issue,
          # i.e. seeing an issue's current issue type, the viewer must be able to access that issue
          if issue_type.is_a?(Platform::Models::IssueTypeWithContext)
            next false unless issue_type.enabled?

            if repository = issue_type.repository
              next permission.typed_can_see?("Repository", repository)
            end

            if issue = issue_type.issue
              next permission.typed_can_see?("Issue", issue)
            end
          end

          # If the issue type is being queried outside of the above scenarios, it implies
          # that it's either being accessed directly, by way of a node query -or- within
          # the context of an organization, i.e. listing all issue types for an orginization.
          # In both of these scenarios, we need to ensure org membership for list/query operations
          # and admin access for write operations.
          owner.async_readable_issue_types_matrix(permission.viewer).then do |matrix|
            issue_type.readable?(matrix)
          end
        end
      end

      field :is_enabled, Boolean, "The issue type's enabled state.", null: false, method: :enabled
      field :name, String, "The issue type's name.", null: false
      field :description, String, "The issue type's description.", null: true
      field :color, Enums::IssueTypeColor, description: "The issue type's color.", null: false
      field :is_private, Boolean, "Whether the issue type is publicly visible.", null: false, method: :private, deprecated: Helpers::PrivateIssueTypeDeprecation::NOTICE
      sig { returns(T::Boolean) }
      def is_private
        # Private issue types are deprecated, however we cannot remove this parameter until this is removed from mobile clients
        # https://github.com/github/mobile/issues/5894
        false
      end

      field :issues, resolver: Resolvers::Issues, description: "The issues with this issue type in the given repository.", connection: true do
        argument :repository_id, ID, "Target repository to load the issues from.", required: true
      end

      field :pinned_fields, [Platform::Unions::IssueFields], description: "An ordered list of issue fields pinned to this type.", null: true
      sig { returns(Promise[Platform::ArrayWrapper]) }
      def pinned_fields
        # Handle different object contexts
        if object.is_a?(Platform::Models::IssueTypeWithContext)
          # Wrapped context: extract the raw object and get repository from context
          issue_type = object.object
          repository = object.repository || object.issue&.repository
        else
          # Direct object: no repository context available
          issue_type = object
          repository = nil
        end

        # Always check organization-level issue_fields feature flag
        return Promise.resolve(ArrayWrapper.new([])) unless IssueFieldsFeature.enabled?(issue_type.owner, actor: context[:viewer])

        # Additionally check repository-level issue_fields feature flag if repository context is available
        if repository
          return Promise.resolve(ArrayWrapper.new([])) unless IssueFieldsFeature.enabled?(repository, actor: context[:viewer])
        end

        Platform::Loaders::PinnedIssueFields.load(issue_type: issue_type, owner: issue_type.owner, viewer: context[:viewer], repository_id: repository&.id).then do |visible_fields|
          next ArrayWrapper.new([]) if visible_fields.empty?

          Platform::Helpers::IssueField.async_filter_accessible(context[:permission], visible_fields).then do |allowed|
            ArrayWrapper.new(allowed)
          end
        end
      end
    end
  end
end
