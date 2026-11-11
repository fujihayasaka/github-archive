# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IssueTypeUpdateInput < Platform::Inputs::Base
      include Platform::Inputs::Suggestable

      docs_category :issues
      feature_flag :update_issue_suggestions
      description "Specifies an Issue Type to set on an issue, with optional metadata such as a rationale."

      argument :issue_type_id, ID, "The ID of the Issue Type to set on this issue. Pass null to clear the issue type.", required: false
    end
  end
end
