# frozen_string_literal: true

require "monolith_twirp/codingagentintegrations/repositories/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Codingagentintegrations
      module Repositories
        class Error < StandardError; end
      end
    end
  end
end
