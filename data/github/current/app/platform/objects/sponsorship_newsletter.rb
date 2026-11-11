# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SponsorshipNewsletter < Platform::Objects::Base
      description "An update sent to sponsors of a user or organization on GitHub Sponsors."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, sponsorship_newsletter)
        sponsorship_newsletter.async_sponsorable.then do |sponsorable|
          org = sponsorable.organization? ? sponsorable : nil
          permission.access_allowed?(:read_sponsorship_newsletter,
            resource: sponsorable,
            sponsorship_newsletter: sponsorship_newsletter,
            current_org: org,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      #
      # Returns a Promise resolving to a Boolean
      def self.async_viewer_can_see?(permission, object)
        object.async_readable_by?(permission.viewer)
      end

      minimum_accepted_scopes ["read:user", "read:org"]

      implements_node templates: [
        [:usn, :user_id, :sponsorship_newsletter_id],
        [:osn, :organization_id, :sponsorship_newsletter_id]
      ], as: "SN", ready_date: "2021-08-21" do |sponsorship_newsletter|
        sponsorship_newsletter.async_sponsorable.then do |sponsorable|
          if sponsorable.organization?
            {
              prefix: :osn,
              organization_id: sponsorable.id,
              sponsorship_newsletter_id: sponsorship_newsletter.id,
            }
          else
            {
              prefix: :usn,
              user_id: sponsorable.id,
              sponsorship_newsletter_id: sponsorship_newsletter.id,
            }
          end
        end
      end

      field :subject, String, "The subject of the newsletter, what it's about.", null: false
      field :body, String, "The contents of the newsletter, the message the sponsorable wanted to give.", null: false

      field :author, Objects::User, description: "The author of the newsletter.", null: true

      def author
        @object.async_author_for(viewer: @context[:viewer])
      end

      field :sponsorable, Interfaces::Sponsorable, "The user or organization this newsletter is from.", null: false,
        method: :async_sponsorable
      field :is_published, Boolean, "Indicates if the newsletter has been made available to sponsors.",
        method: :published?, null: false

      field :is_for_all_tiers, Boolean, visibility: {
        internal: { environments: [:enterprise] },
        under_development: { environments: [:dotcom] },
      }, description: "Indicates if this newsletter is available to all sponsorship tiers", method: :for_all_tiers?,
        null: false

      field :sponsors_tiers, Connections.define(Objects::SponsorsTier), visibility: {
        internal: { environments: [:enterprise] },
        under_development: { environments: [:dotcom] },
      }, description: "The tiers that have been granted direct access to this newsletter", connection: true,
        null: true

      created_at_field
      updated_at_field
    end
  end
end
