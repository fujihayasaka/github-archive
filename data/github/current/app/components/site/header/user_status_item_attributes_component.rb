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
          end

          if emoji
            emoji_attrs = emoji_attributes(emoji, {
              class: "emoji",
              align: "absmiddle"
            })

            status_attributes[:emojiAttributes] = {
              tag: emoji_attrs[:tag],
              imgPath: image_path(emoji_attrs[:img_path]),
              attributes: emoji_attrs[:attributes]
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
