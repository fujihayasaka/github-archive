# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module UpdatableComment
      include Platform::Interfaces::Base
      description "Comments that can be updated."

      field :viewer_cannot_update_reasons, [Enums::CommentCannotUpdateReason], description: "Reasons why the current viewer can not update this comment.", null: false

      def viewer_cannot_update_reasons
        @object.async_viewer_cannot_update_reasons(@context[:viewer])
      end
    end
  end
end
