# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SavedReply < Platform::Objects::Base
      description "A Saved Reply is text a user can use to reply quickly."

      minimum_accepted_scopes ["read:user"]

      implements_node templates: [[:usr, :user_id, :saved_reply_id]], as: "SR", ready_date: "2021-06-24" do |saved_reply|
        {
          prefix: :usr,
          user_id: saved_reply.user_id,
          saved_reply_id: saved_reply.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      sig { params(permission: Platform::Authorization::Permission, reply: T.untyped).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_api_can_access?(permission, reply)
        reply.async_user.then do |user|
          permission.access_allowed?(:v4_read_user_private, resource: user, current_repo: nil, current_org: nil, allow_integration: false, allow_user_via_granular_actor: false)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_viewer(object)
      end

      database_id_field

      field :user, Interfaces::Actor, method: :async_user, description: "The user that saved this reply.", null: true
      field :title, String, "The title of the saved reply.", null: false
      field :body, String, "The body of the saved reply.", null: false
      field :body_html, Scalars::HTML, description: "The saved reply body rendered to HTML.", null: false
      def body_html
        markdown = CommonMarker.render_html(@object.body || "", [:UNSAFE, :GITHUB_PRE_LANG], %i[tagfilter table strikethrough autolink])
        GitHub::Goomba::SimplePipeline.to_html(markdown)
      end
    end
  end
end
