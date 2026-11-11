# typed: true
# frozen_string_literal: true

require "delegate"

module Platform
  module Objects
    module Concerns
      module DiscussionPostAsAdmin
        extend ActiveSupport::Concern

        # Admin proxy class for displaying "Admin" placeholder instead of actual user info
        # Used when post_as_admin is true but viewer doesn't have permission to see original author
        AdminProxy = Class.new(SimpleDelegator) do
          def login
            "admin"
          end

          def display_name
            "admin"
          end

          def display_login
            "admin"
          end

          def login_for_api(*_args)
            "admin"
          end

          def display_login_legacy
            "admin"
          end
        end

        private

        # Common logic for handling author visibility in post_as_admin scenarios
        # @param object [Discussion, DiscussionComment] The discussion or comment object
        # @param context [Hash] The GraphQL context
        # @return [Promise] Promise resolving to the appropriate author object
        def handle_post_as_admin_author(object, context)
          return object.async_user unless object.post_as_admin?

          viewer = context[:viewer]

          # Check if feature flag is enabled for the viewer or globally for anonymous users
          feature_enabled = FeatureFlag.vexi.enabled?(:discussion_post_as_admin, viewer, default: false)

          return object.async_user unless feature_enabled

          Promise.all([
            object.async_user,
            context[:viewer] ? object.repository.async_action_or_role_level_for(context[:viewer], include_custom_roles: false) : Promise.resolve(nil)
          ]).then do |author, permission|
            if viewer_can_see_admin_author?(viewer, permission)
              if object.is_a?(::Discussion)
                next unless author
                next if author.is_a?(Organization)

                author.async_business_user_accounts.then do
                  context[:permission].typed_can_see?("User", author).then do |can_read|
                    if can_read && !author.hide_from_user?(context[:viewer])
                      author
                    else
                      nil
                    end
                  end
                end
              else
                author
              end
            else
              ghost_user = ::User.ghost
              AdminProxy.new(ghost_user)
            end
          end
        end

        # @param viewer [User, nil] The viewing user
        # @param permission [Symbol, nil] The viewer's repository permission level
        # @return [Boolean] true if the viewer can see the original author
        def viewer_can_see_admin_author?(viewer, permission)
          return false unless viewer
          return true if viewer&.site_admin?
          return true if viewer&.employee?
          return true if [:admin, :maintain].include?(permission)

          false
        end
      end
    end
  end
end
