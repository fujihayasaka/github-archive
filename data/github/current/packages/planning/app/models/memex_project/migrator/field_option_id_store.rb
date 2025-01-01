# typed: true
# frozen_string_literal: true

class MemexProject::Migrator::FieldOptionIdStore
  extend Forwardable
  def_delegators :@store, :dig

  def initialize(memex_project, spec)
    @memex_project = memex_project
    @spec = spec
    @store = {}

    if spec[:status_field]
      status_options_by_name = memex_project.status_column.settings_options.index_by { |o| o[:name] }
      spec_options_by_name = spec[:status_field][:settings][:options].index_by { |o| o[:name].strip }

      @store[spec[:status_field][:id]] = spec_options_by_name.reduce({}) do |result, (name, spec_option)|
        result[spec_option[:id]] = status_options_by_name[name][:id]
        result
      end
    end
  end
end
