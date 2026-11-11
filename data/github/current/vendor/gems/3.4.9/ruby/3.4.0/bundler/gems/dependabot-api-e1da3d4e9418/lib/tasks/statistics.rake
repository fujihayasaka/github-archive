# frozen_string_literal: true

# Makes `rake stats` relevant to our setup. Without this, it wouldn't count
# any code in the actions, coach or state_machines folders
task stats: "dependabot:statsetup"

namespace :dependabot do
  # rubocop:disable Rails/RakeEnvironment
  task :statsetup do
    require "rails/code_statistics"

    additional_types = [
      ["Actions", "app/actions"],
      ["Coach (Controllers)", "app/coach"],
      ["State Machines", "app/state_machines"],
    ]

    additional_types = additional_types.map do |name, dir|
      [name, "#{File.dirname(Rake.application.rakefile_location)}/#{dir}"]
    end

    additional_types.select! { |_, dir| File.directory?(dir) }
    additional_types.each { |type, dir| ::STATS_DIRECTORIES << [type, dir] }

    ::STATS_DIRECTORIES.
      sort_by! do |type, _|
        # Sort alphabetically, with test directories listed last
        type.end_with?("test", "specs") ? "B #{type}" : "A  #{type}"
      end
  end
  # rubocop:enable Rails/RakeEnvironment
end
