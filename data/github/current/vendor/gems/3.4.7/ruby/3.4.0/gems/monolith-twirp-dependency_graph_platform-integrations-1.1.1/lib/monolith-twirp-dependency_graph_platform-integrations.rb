# frozen_string_literal: true

require "monolith_twirp/dependency_graph_platform/integrations/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module DependencyGraphPlatform
      module Integrations
        class Error < StandardError; end
      end
    end
  end
end
