# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Pullsd
      sig { returns(T.nilable(String)) }
      attr_accessor :pullsd_url

      sig { returns(T.nilable(String)) }
      attr_accessor :pullsd_hmac_key
    end
  end

  extend Config::Pullsd
end
