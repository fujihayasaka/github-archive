# typed: true
# frozen_string_literal: true

# Allows Ja3 hashes (e.g., 07ff1e545ef8ab3fcf8a4dc9272221c2) to be used as
# Flipper actors.
module GitHub
  class FlipperJa3Hash
    include GitHub::FlipperActor
    include GitHub::VexiActor

    def initialize(ja3_hash)
      @ja3_hash = ja3_hash
      freeze
    end

    def ==(other)
      self.class == other.class && vexi_id == other.vexi_id
    end
    alias_method :eql?, :==

    def flipper_id
      "Ja3:#{@ja3_hash}"
    end

    def vexi_id
      flipper_id
    end
  end
end
