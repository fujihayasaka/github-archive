# typed: true
# frozen_string_literal: true

require_relative "monolith_twirp/attester/version"
require_relative "monolith_twirp/attester/request_hmac"

Dir["#{File.dirname(__FILE__)}/**/*_twirp.rb"].each { |file| require_relative file }
