# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class UserStatus < Platform::Objects::Base

      description "The user's description of what they're currently doing."

      implements_node templates: [[:us, :user_id, :user_status_id]], as: "US", ready_date: "2021-06-25" do |user_status|
        {
          prefix: :us,
          user_id: user_status.user_id,
          user_status_id: user_status.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, user_status)
        user_status.async_organization.then do |org|
          user_status.async_user.then do |user|
            if org
              permission.access_allowed?(:get_member, resource: org, member: user,
                                         current_repo: nil, current_org: org,
                                         allow_integrations: true, allow_user_via_granular_actor: true)
            else
              public_resource = Platform::PublicResource.new(resource: user)
              permission.access_allowed?(:read_user_public, resource: public_resource,
                                       current_repo: nil, current_org: nil,
                                       allow_integrations: true, allow_user_via_granular_actor: true)
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, user_status)
        user_status.async_readable_by?(permission.viewer)
      end

      scopeless_tokens_as_minimum

      created_at_field

      updated_at_field

      field :user, Objects::User, "The user who has this status.", null: false, method: :async_user

      field :organization, Objects::Organization,
        "The organization whose members can see this status. If null, this status " \
        "is publicly visible.", null: true, method: :async_organization

      field :emoji, String, "An emoji summarizing the user's status.", null: true

      field :emoji_html, Scalars::HTML, description: "The status emoji as HTML.", null: true

      field :message, String, "A brief message describing what the user is doing.", null: true

      field :expires_at, Scalars::DateTime, "If set, the status will not be shown after this date.",
        null: true

      field :message_html, Scalars::HTML, description: "The status message as HTML.", null: true,
                                          visibility: :internal do
        argument :link_mentions, Boolean,
          "Should mentioned users, organizations, and teams be linked.",
          default_value: true, required: false
      end

      def message_html(link_mentions:)
        @object.async_message_html(viewer: @context[:viewer], link_mentions: link_mentions)
      end

      field :indicates_limited_availability, Boolean,
        description: "Whether this status indicates the user is not fully available on GitHub.",
        null: false, method: :limited_availability?
    end
  end
end
