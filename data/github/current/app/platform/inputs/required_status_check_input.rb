# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RequiredStatusCheckInput < Platform::Inputs::Base
      graphql_name "RequiredStatusCheckInput"
      description "Specifies the attributes for a new or updated required status check."

      argument :context, String, "Status check context that must pass for commits to be accepted to the matching branch.", required: true, as: :status_context
      argument :app_id, ID, "The ID of the App that must set the status in order for it to be accepted. Omit this value to use whichever app has recently been setting this status, or use \"any\" to allow any app to set the status.", required: false
    end
  end
end
