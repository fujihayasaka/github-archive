# typed: false
# frozen_string_literal: true

class ProjectColumn
  module MigrationDependency
    extend ActiveSupport::Concern

    def to_memex_specification
      {
        id: id.to_s,
        name: name,
        color: color,
      }.compact
    end
  end
end
