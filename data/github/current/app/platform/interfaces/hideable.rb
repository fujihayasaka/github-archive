# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Hideable
      include Platform::Interfaces::Base
      docs_category :meta
      description "Top-level content whose body can be hidden as a moderation action."
      visibility :internal

      field :viewer_can_hide, Boolean, description: "Check if the current viewer can hide this object's body.", visibility: :internal, null: false
      def viewer_can_hide
        @object.async_hideable_by?(@context[:viewer])
      end

      field :viewer_can_unhide, Boolean, description: "Check if the current viewer has permission to restore visibility of this object's body if it's hidden.", visibility: :internal, null: false
      def viewer_can_unhide
        @object.async_unhideable_by?(@context[:viewer])
      end
    end
  end
end
