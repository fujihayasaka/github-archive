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

          Promise.all([
            object.async_user,
            object.repository.async_adminable_by?(context[:viewer]),
          ]).then do |author, repository_admin_viewer|
            if repository_admin_viewer
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
      end
    end
  end
end
