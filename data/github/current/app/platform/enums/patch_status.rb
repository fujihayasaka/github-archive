# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PatchStatus < Platform::Enums::Base
      description "The possible types of patch statuses."

      value "ADDED", "The file was added. Git status 'A'.", value: :added
      value "DELETED", "The file was deleted. Git status 'D'.", value: :deleted
      value "RENAMED", "The file was renamed. Git status 'R'.", value: :renamed
      value "COPIED", "The file was copied. Git status 'C'.", value: :copied
      value "MODIFIED", "The file's contents were changed. Git status 'M'.", value: :modified
      value "CHANGED", "The file's type was changed. Git status 'T'.", value: :changed
    end
  end
end
