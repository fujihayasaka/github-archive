# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class MobileSuggestedChangeInput < Platform::Inputs::Base
      description "Describes a suggested change to a file to be applied in a new commit."
      required_capabilities [:mobile_only_schema_mask]

      argument :comment_id, ID, "ID of the comment with the suggested change.", required: true
      argument :suggested_change_id, ID, "ID of the suggested change", required: true
    end
  end
end
