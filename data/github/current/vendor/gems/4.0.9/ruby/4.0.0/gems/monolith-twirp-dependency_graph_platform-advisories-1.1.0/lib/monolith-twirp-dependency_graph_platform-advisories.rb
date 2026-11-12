# frozen_string_literal: true

require "monolith_twirp/dependency_graph_platform/advisories/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module DependencyGraphPlatform
      module Advisories
        class Error < StandardError; end
      end
    end
  end
end
