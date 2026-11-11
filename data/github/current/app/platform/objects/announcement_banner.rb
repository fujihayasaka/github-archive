# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AnnouncementBanner < Platform::Objects::Base
      model_name "EnterpriseBanner"

      description "An announcement banner for an enterprise or organization."

      def self.async_viewer_can_see?(permission, banner)
        banner.async_owner.then do |owner|
          if owner.is_a?(::Business)
            owner.member?(permission.viewer)
          else
            name = if owner.is_a?(::Business)
              "Business"
            elsif owner.is_a?(::Organization)
              "Organization"
            elsif owner.is_a?(::Repository)
              "Repository"
            else
              return false
            end

            permission.typed_can_see?(name, owner)
          end
        end
      end

      def self.async_api_can_access?(permission, banner)
        banner.async_owner.then do |owner|
          if owner.is_a?(::Business)
            permission.access_allowed?(
              :read_announcement_banner,
              resource: owner,
              business: owner,
              current_org: nil,
              current_repo: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false
            )
          else
            if owner.is_a?(::Organization)
              current_org = owner
              current_repo = nil
            elsif owner.is_a?(::Repository)
              current_org = nil
              current_repo = owner
            end

            owner.async_business.then do |business|
              permission.access_allowed?(
                :read_announcement_banner,
                resource: owner,
                business: business,
                current_org:,
                current_repo:,
                allow_integrations: true,
                allow_user_via_granular_actor: true
              )
            end
          end
        end
      end

      field :message, String, "The text of the announcement"
      field :expires_at, Platform::Scalars::DateTime, "The expiration date of the announcement, if any", null: true
      field :created_at, Platform::Scalars::DateTime, "The date the announcement was created", null: false

      field :is_user_dismissible, Boolean, "Whether the announcement can be dismissed by the user", null: false

      def is_user_dismissible
        @object.dismissible
      end

      field :is_dismissed, Boolean, "Whether the announcement has been dismissed by the viewer", null: false, visibility: :internal

      def is_dismissed
        Platform::Loaders::BannerDismissalsByUser.load(@object.id, @context[:viewer].id).then do |dismissed|
          dismissed.present?
        end
      end
    end
  end
end
