# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class PackageFileOrder < Platform::Inputs::Base
      description "Ways in which lists of package files can be ordered upon return."

      argument :field, Enums::PackageFileOrderField, "The field in which to order package files by.", required: false
      argument :direction, Enums::OrderDirection, "The direction in which to order package files by the specified field.", required: false
    end
  end
end
