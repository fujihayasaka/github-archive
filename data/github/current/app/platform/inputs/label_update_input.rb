# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class LabelUpdateInput < Platform::Inputs::Base
      include Platform::Inputs::Suggestable

      docs_category :issues
      feature_flag :update_issue_suggestions
      description "Specifies a Label to set on an issue, with optional metadata such as a rationale."

      argument :label_id, ID, "The ID of the Label.", required: true, loads: Objects::Label
    end
  end
end
