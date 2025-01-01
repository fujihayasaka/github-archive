# typed: true
# frozen_string_literal: true

require_relative "proto/trust-metadata-api/version"
require_relative "proto/trust-metadata-api/request_hmac"

Dir["#{File.dirname(__FILE__)}/**/*_twirp.rb"].each { |file| require_relative file }
