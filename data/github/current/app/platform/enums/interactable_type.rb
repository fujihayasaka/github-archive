# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class InteractableType < Platform::Enums::Base
      description "Types of objects a user can have interacted with."
      visibility :internal

      value "ISSUE", "Issues the user has interacted with.", value: :issue
      value "PULL_REQUEST", "Pull requests the user has interacted with.", value: :pull_request
    end
  end
end
