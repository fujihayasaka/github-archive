# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectNextOrderField < Platform::Enums::Base
      description "Properties by which the return project can be ordered."
      mobile_only true

      value "TITLE", "The project's title", value: "title"
      value "NUMBER", "The project's number", value: "number"
      value "UPDATED_AT", "The project's date and time of update", value: "updated_at"
      value "CREATED_AT", "The project's date and time of creation", value: "created_at"
    end
  end
end
