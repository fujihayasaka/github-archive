# typed: true
# frozen_string_literal: true

class MemexFieldGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  def setup_field_files
    template "field.rb.erb", "packages/planning/app/models/memex_project_column/field/#{file_name}.rb"
    template "field_test.rb.erb", "packages/planning/test/models/memex_project_column/field/#{file_name}_test.rb"
    template "field_test_helper.rb.erb", "test/test_helpers/planning/memex_project_column/#{file_name}_helper.rb"
  end

  def update_field_registry
    field_dependency_file_path = "packages/planning/app/models/memex_project_column/field_dependency.rb"
    new_class_name = "MemexProjectColumn::Field::#{class_name}"
    class_to_insert_after = find_previous_field_class(new_class_name)
    inject_into_file(field_dependency_file_path, "\n      #{new_class_name}", after: class_to_insert_after, force: true)
  end

  def update_document_interface_types
    types_file_path = "lib/elastomer/interfaces/document/memex_project_item.rb"
    new_class_name = "MemexProjectColumn::Field::#{class_name}"
    class_to_insert_after = find_previous_field_class(new_class_name)
    value_type_to_insert_after = "#{class_to_insert_after.gsub("MemexProjectColumn::Field::", "")}Value"
    new_value_type = "#{class_name}Value"

    inject_into_file(
      types_file_path,
      "\n        # TODO: Update this placeholder String type to match the type of the #{class_name} field's value" +
      "\n        #{new_value_type} = T.type_alias { T.nilable(String) }",
      after: /#{value_type_to_insert_after} = T\.type_alias.*\}/,
      force: true
    )
    inject_into_file(
      types_file_path,
      "\n            #{new_value_type},",
      after: /#{value_type_to_insert_after},/,
      force: true
    )
  end

  private

  # Finds the previous field class in the alphabetically sorted registry and returns it to insert the new class in the correct location.
  def find_previous_field_class(new_class_name)
    new_registry = MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY.push(new_class_name).sort
    idx = T.must_because(new_registry.index(new_class_name)) { "new_class_name was just pushed to the registry" }
    new_registry[idx - 1]
  end
end
