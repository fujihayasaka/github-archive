# typed: true
# frozen_string_literal: true

class MemexProject::Migrator::Specification
  include ActiveModel::Validations
  extend Forwardable

  def_delegators :@data, :[], :fetch, :dig, :slice

  DEFAULT_SCHEMA_PATH = File.join(Rails.root, "packages/planning/app/models/memex_project/migrator/schemas/v1/project.json")

  attr_reader :data, :schema

  validate :conforms_to_schema
  validate :field_ids_are_unique
  validate :field_option_ids_are_unique
  validate :workflow_names_are_unique

  def initialize(data, json_schema: nil)
    @data = data
    @schema = JsonSchema.parse!(json_schema || JSON.parse(File.read(DEFAULT_SCHEMA_PATH)))
    @schema.expand_references!
  end

  private def conforms_to_schema
    schema.validate(data.deep_stringify_keys).second.each do |schema_validation_error|
      errors.add(:data, schema_validation_error.message)
    end
  end

  private def field_ids_are_unique
    reference_field_ids = data.fetch(:fields, []).map { |f| f[:id] }
    reference_field_ids << data.dig(:status_field, :id)
    reference_field_ids.compact!

    find_duplicates(reference_field_ids).each do |duplicate|
      errors.add(:base, "cannot reuse field id #{duplicate}")
    end
  end

  private def field_option_ids_are_unique
    single_select_fields = data.fetch(:fields, []).select { |f| f[:type] == "single_select" }
    single_select_fields << data[:status_field]
    single_select_fields.compact!

    single_select_fields.each do |field|
      option_ids = field.dig(:settings, :options).map { |o| o[:id] }
      find_duplicates(option_ids).each do |duplicate|
        errors.add(:base, "cannot reuse option id #{duplicate} for field #{field[:id]}")
      end
    end
  end

  private def workflow_names_are_unique
    workflow_names = data.fetch(:workflows, []).map { |w| w[:name] }
    find_duplicates(workflow_names).each do |duplicate|
      errors.add(:base, "cannot reuse workflow name #{duplicate}")
    end
  end

  private def find_duplicates(array)
    array.group_by(&:to_s).select { |_, ids| ids.length > 1 }.map(&:first)
  end
end
