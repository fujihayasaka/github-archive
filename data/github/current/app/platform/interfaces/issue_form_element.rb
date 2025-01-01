# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module IssueFormElement
      include Platform::Interfaces::Base

      description "An issue form element"

      field :type, String, "The issue form element type", null: false, method: :type

      field :id, String, "The identifier for the element.  If provided, the id is the canonical identifier for the field in URL query parameter prefills.", null: true
    end
  end
end
