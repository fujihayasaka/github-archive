# typed: true
# frozen_string_literal: true

class ComponentSystemTestGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)
  check_class_collision suffix: "SystemTest"

  class_option :system_test_path, type: :string, default: "test/system/components"

  def create_test_file
    template "component_system_test.rb", File.join(options[:system_test_path], class_path, "#{file_name}_system_test.rb")
  end
end
