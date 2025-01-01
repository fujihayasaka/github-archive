# typed: true
# frozen_string_literal: true

module GitHub
  module Hex
    def self.load(bin)
      bin.unpack("H*")[0] if bin
    end

    def self.dump(str)
      [str].pack("H*") if str
    end
  end
end
