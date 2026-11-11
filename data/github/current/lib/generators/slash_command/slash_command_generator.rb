# typed: true
# frozen_string_literal: true

class SlashCommandGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  class_option :description, type: :string, default: nil

  def generate_command_class
    in_root do
      yaml_string = File.read("config/slash_commands.yml")
      data = YAML.safe_load yaml_string

      data["slash_commands"] << "SlashCommands::#{class_name}Command"
      data["slash_commands"].sort!.uniq!

      output = YAML.dump data
      File.write "config/slash_commands.yml", output
    end

    template "slash_command_class_template.rb.erb", "app/models/slash_commands/#{file_name}_command.rb"
    template "slash_command_test_template.rb.erb", "test/models/slash_commands/#{file_name}_command_test.rb"
  end
end
