# typed: true
# frozen_string_literal: true

require "ostruct"

module Coders
  class OauthApplicationCoder < Coders::Base

    data_accessors :scopes

  end
end
