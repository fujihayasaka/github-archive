# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module Editor
      def self.for(editable:, context:)
        editable.async_latest_user_content_edit.then do |user_content_edit|
          user_content_edit&.async_editor&.then do |user|
            next unless user
            next if user.is_a?(::Organization)

            context[:permission].typed_can_see?("User", user).then do |readable|
              if readable && !user.hide_from_user?(context[:viewer])
                user
              end
            end
          end
        end
      end
    end
  end
end
