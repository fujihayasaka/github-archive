# typed: true
# frozen_string_literal: true

require "rails/generators"

class SeedGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  class_option :codespace, type: :boolean, default: false, desc: "Adds this seed to the default seeds run on codespace creation."
  class_option :codespace_devcontainer_name, type: :string, default: "", desc: "Adds this seed to the specified devcontainer."

  # The seed_runner is actually what runs all the seeding code.
  def generate_seed_runner
    template "runner.rb.erb", "script/seeds/runners/#{file_name}.rb"
  end

  # The testfile for the seed runner class.
  def generate_seed_runner_test
    template "runner_test.rb.erb", "test/script/seeds/runners/#{file_name}_test.rb"
  end

  # The seed_file invokes the runner. The file is invoked by `.devcontainer/run_seeds.rb` in the
  # on-create-command.sh script and establishes it as a default codespace seed.
  def generate_devcontainer_seed_invocation_file
    return unless options[:codespace]
    if options[:codespace_devcontainer_name].present?
      template "devcontainer_seed.rb.erb", ".devcontainer/#{options[:codespace_devcontainer_name]}/seed/#{devcontainer_seed_file_name}.rb"
    else
      template "devcontainer_seed.rb.erb", ".devcontainer/seed/#{devcontainer_seed_file_name}.rb"
    end
  end

  def add_command_to_app
    to_add = <<-EOF

    desc "#{file_name}", Seeds::Runner::#{class_name}.help.lines.first
    long_desc Seeds::Runner::#{class_name}.help
    def #{file_name}
      Seeds::Runner::#{class_name}.execute(options)
    end
    EOF

    inject_into_file "script/seeds/app.rb", to_add, before: /^\s+desc \"console\"/
  end

  def devcontainer_seed_file_name
    @devcontainer_seed_file_name = "#{Time.now.to_i}_#{file_name}" if @devcontainer_seed_file_name.blank?
    @devcontainer_seed_file_name
  end

  def devcontainer_seed_path
    if options[:codespace_devcontainer_name].present?
      "#{options[:codespace_devcontainer_name]}/seed/#{devcontainer_seed_file_name}.rb"
    else
      "seed/#{devcontainer_seed_file_name}.rb"
    end
  end

  def require_path
    default_path = "../../script/seeds/runners/#{file_name}.rb"
    options[:codespace_devcontainer_name].present? ? "../#{default_path}" : default_path
  end
end
