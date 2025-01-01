# frozen_string_literal: true

require "monolith_twirp/copilot/token/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Copilot
      module Token
        class Error < StandardError; end
      end
    end
  end
end
