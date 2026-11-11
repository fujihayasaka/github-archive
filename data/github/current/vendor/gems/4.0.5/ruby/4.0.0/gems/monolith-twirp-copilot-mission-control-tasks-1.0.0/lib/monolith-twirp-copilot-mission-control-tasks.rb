# frozen_string_literal: true

require "monolith_twirp/copilot-mission-control/tasks/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module CopilotMissionControl
      module Tasks
        class Error < StandardError; end
      end
    end
  end
end
