# frozen_string_literal: true

require "monolith_twirp/scribe/plans/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Scribe
      module Plans
        class Error < StandardError; end
      end
    end
  end
end
