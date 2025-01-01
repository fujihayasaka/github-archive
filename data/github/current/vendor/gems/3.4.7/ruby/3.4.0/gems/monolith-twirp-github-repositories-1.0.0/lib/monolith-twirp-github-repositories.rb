# frozen_string_literal: true

require "monolith_twirp/github/repositories/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Github
      module Repositories
        class Error < StandardError; end
      end
    end
  end
end
