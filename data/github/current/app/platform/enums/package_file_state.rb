# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PackageFileState < Platform::Enums::Base
      description "The possible states of a package file."

      visibility :internal

      value "NEW", "Package file doesn't have a blob backing it.", value: :new
      value "UPLOADED", "All Package file contents have been uploaded.", value: :uploaded
    end
  end
end
