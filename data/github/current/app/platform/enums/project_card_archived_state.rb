# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectCardArchivedState < Platform::Enums::Base
      description "The possible archived states of a project card."

      value "ARCHIVED", "A project card that is archived", value: :archived, deprecated: Helpers::ProjectDeprecation::Notice
      value "NOT_ARCHIVED", "A project card that is not archived", value: :not_archived, deprecated: Helpers::ProjectDeprecation::Notice
    end
  end
end
