# typed: true
# frozen_string_literal: true

namespace :enterprise do
  namespace :copilot_cli do
    task :create, [] => [:environment] do
      next unless GitHub.enterprise? || Rails.env.development?

      Apps::Privileged::CopilotCLI.seed_database!
    end
  end
end
