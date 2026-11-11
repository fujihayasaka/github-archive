# frozen_string_literal: true

require "monolith_twirp/actionsdatastream/core/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Actionsdatastream
      module Core
        class Error < StandardError; end
      end
    end
  end
end
