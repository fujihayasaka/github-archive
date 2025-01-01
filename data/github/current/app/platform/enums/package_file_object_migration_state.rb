# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PackageFileObjectMigrationState < Platform::Enums::Base
      description "The possible object migration states of a package file."

      visibility :internal

      value "UNMIGRATED", "Package file object is stored in its initial data store.", value: "unmigrated"
      value "COMPLETE", "Package file object is stored in its destination data store.", value: "complete"
    end
  end
end
