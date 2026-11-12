# frozen_string_literal: true

require "monolith_twirp/partitioning/pull_requests/version"

Dir["#{File.dirname(__FILE__)}/monolith_twirp/**/*_twirp.rb"].each { |file| require file }

module Monolith
  module Twirp
    module Partitioning
      module PullRequests
        class Error < StandardError; end
      end
    end
  end
end
