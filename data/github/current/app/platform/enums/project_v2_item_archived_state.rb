# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2ItemArchivedState < Platform::Enums::Base
      docs_category :projects
      description "The possible archived states of a `ProjectV2Item`."

      value "ARCHIVED", "A project item that is archived", value: :archived
      value "NOT_ARCHIVED", "A project item that is not archived", value: :not_archived
    end
  end
end
