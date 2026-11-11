# frozen_string_literal: true

require "monolith_twirp/dependency_graph_platform/actions/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module DependencyGraphPlatform
      module Actions
        class Error < StandardError; end
      end
    end
  end
end
