# typed: true
# frozen_string_literal: true

require "test_helper"

# Forcefully pull in twirp.rb to get error classes
::PackageRegistry::Twirp

module PackageRegistry
  module Twirp
    class NullClientTest < GitHub::TestCase
      setup do
        @subject = NullClient.new
      end

      test "#anything" do
        response = @subject.anything
        assert_equal ::Twirp::ClientResp, response.class
        assert_equal ::Twirp::Error, response.error.class
      end
    end
  end
end
