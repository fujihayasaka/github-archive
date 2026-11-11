# typed: true
# frozen_string_literal: true

module Site
  module Header
    include StaticAssetHelper

    class UserStatusItemAttributesComponent < UserStatusItemComponent
      def attributes
        {}.tap do |status_attributes|
          if user_status
            status_attributes[:messageHtml] = user_status.message_html(viewer: current_user, link_mentions: false)
            status_attributes[:message] = user_status.message
            status_attributes[:limitedAvailability] = user_status.limited_availability?
            if user_status.organization
              status_attributes[:organization] = {
                globalRelayId: user_status.organization.global_relay_id,
                id: user_status.organization.id,
              }
            end
          end

          if current_user
            user_status_when_not_expired = current_user.user_status_when_not_expired
            status_attributes[:expiresAt] = user_status_when_not_expired&.expires_at&.iso8601
            status_attributes[:expiresIn] = user_status_when_not_expired&.expires_at ? helpers.current_user_status_expires_at(user_status_when_not_expired.expires_at) : nil
            status_attributes[:organizationOptions] = current_user.organizations.take(100).sort_by(&:display_login).map do |org|
              {
                label: org.display_login,
                value: org.id,
                globalRelayId: org.global_relay_id,
              }
            end
          end

          status_attributes[:suggestions] = helpers.predefined_user_statuses_with_emoji.map do |emoji, message|
            emoji_attrs = emoji_attributes(emoji, {
              class: "emoji",
              align: "absmiddle"
            })

            suggestion = {
              message: message,
              emojiAttributes: {
                tag: emoji_attrs[:tag],
                imgPath: image_path(emoji_attrs[:img_path]),
                attributes: emoji_attrs[:attributes],
                name: emoji.name,
              }
            }

            if emoji_attrs[:tag] == "g-emoji"
              suggestion[:emojiAttributes][:raw] = emoji.raw
            end

            suggestion
          end
          status_attributes[:expirationIntervals] = UserStatusesHelper.expiration_intervals.map do |interval|
            { label: interval[:words], time: interval[:time] }
          end

          if emoji
            emoji_attrs = emoji_attributes(emoji, {
              class: "emoji",
              align: "absmiddle"
            })

            status_attributes[:emojiAttributes] = {
              tag: emoji_attrs[:tag],
              imgPath: image_path(emoji_attrs[:img_path]),
              attributes: emoji_attrs[:attributes],
              name: emoji.name,
            }

            if emoji_attrs[:tag] == "g-emoji"
              status_attributes[:emojiAttributes][:raw] = emoji.raw
            end
          end
        end
      end

      # Overriding this method enables us to do eg. this in ERB:
      #
      # <%= render(UserStatusItemAttributesComponent.new).to_json %>
      #
      def render_in(...)
        # set the view context so helpers, etc work as expected
        super

        # return the attributes hash instead of a string of HTML
        attributes
      end

      # Prevent the component from rendering its template, which doesn't exist
      def render?
        false
      end
    end
  end
end
