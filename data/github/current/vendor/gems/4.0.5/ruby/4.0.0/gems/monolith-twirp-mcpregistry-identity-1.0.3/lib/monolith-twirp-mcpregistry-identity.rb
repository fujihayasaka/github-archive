# frozen_string_literal: true

require "monolith_twirp/mcpregistry/identity/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Mcpregistry
      module Identity
        class Error < StandardError; end
      end
    end
  end
end
