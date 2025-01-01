# frozen_string_literal: true

require "monolith_twirp/pullsd/repositories/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Pullsd
      module Repositories
        class Error < StandardError; end
      end
    end
  end
end
