# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module OrgBlockable
      include Platform::Interfaces::Base
      description "Entities that have the action to block the creating user."
      required_capabilities [:mobile_only_schema_mask]

      field :viewer_can_block_from_org, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Check if the current viewer can block the author of this content from the owning organization.", null: false

      field :viewer_can_unblock_from_org, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Check if the current viewer can unblock the author of this content from the owning organization.", null: false

      def viewer_can_block_from_org
        @object.async_viewer_can_block_from_org?(@context[:viewer])
      end

      def viewer_can_unblock_from_org
        @object.async_viewer_can_unblock_from_org?(@context[:viewer])
      end
    end
  end
end
