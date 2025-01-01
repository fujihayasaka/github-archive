# typed: true
# frozen_string_literal: true

require "fast/helper"
require_relative "../app/models/spokesapi/util"

module SpokesAPI
  class SpokesAPIUtilTest < Test::Fast::TestCase
    include SpokesAPI::Util

    def test_valid_oid?
      %w[
        0123456789abcdef0123456789abcdef01234567
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      ].each do |input|
        assert valid_oid?(input)
      end

      [
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "azaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "azaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa💣",
        "0123456789abcdef",
        "AA💣",
        :aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,
        nil
      ].each do |input|
        refute valid_oid?(input)
      end
    end
  end
end
