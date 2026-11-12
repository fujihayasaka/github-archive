# frozen_string_literal: true

require "monolith_twirp/scribe/artifacts/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Scribe
      module Artifacts
        class Error < StandardError; end
      end
    end
  end
end
