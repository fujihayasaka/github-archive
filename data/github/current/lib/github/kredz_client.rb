# typed: true
# frozen_string_literal: true

require "github-kredz"

module GitHub
  module KredzClient
    autoload :Credz, "github/kredz_client/credz"
    autoload :Varz, "github/kredz_client/varz"

    Error = Class.new(RuntimeError)
    ServiceUnavailable = Class.new(Error)
  end
end
