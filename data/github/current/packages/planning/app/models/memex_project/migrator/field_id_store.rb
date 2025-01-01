# typed: true
# frozen_string_literal: true

class MemexProject::Migrator::FieldIdStore
  extend Forwardable
  def_delegators :@store, :dig

  def initialize(memex_project, spec)
    @memex_project = memex_project
    @spec = spec
    @store = {}

    if spec[:status_field]
      @store[spec[:status_field][:id]] = memex_project.status_column.id
    end

    # TODO: Add support for storing ids from spec[:fields].
  end
end
