# frozen_string_literal: true

namespace :ecosystem do
  desc "Onboard a new ecosystem - Usage: rake ecosystem:onboard[ecosystem_name,package_manager_name,mode]"
  task :onboard, %i(ecosystem_name package_manager_name mode) => [:environment] do |_task, args|
    require_relative "../ecosystem_onboarding"

    ecosystem_name = args[:ecosystem_name]
    package_manager_name = args[:package_manager_name] || ecosystem_name
    mode = args[:mode] || "interactive"

    unless ecosystem_name
      puts "Error: ecosystem_name is required"
      puts "Usage: rake ecosystem:onboard[ecosystem_name,package_manager_name,mode]"
      puts "  ecosystem_name: Required - The name of the ecosystem (e.g., 'conda', 'uv')"
      puts "  package_manager_name: Optional - Package manager name (defaults to ecosystem_name)"
      puts "  mode: Optional - 'interactive' (default), 'skip', or 'overwrite'"
      exit 1
    end

    onboarding = EcosystemOnboarding.new(
      ecosystem_name: ecosystem_name,
      package_manager_name: package_manager_name,
      mode: mode
    )

    onboarding.run
  end
end
