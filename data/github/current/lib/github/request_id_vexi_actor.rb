# typed: strict
# frozen_string_literal: true

# Allows request IDs (e.g., E6C0:2E0959:BD5865:B769F4:68AAAD1C) to be used as Vexi actors.
module GitHub
  class RequestIdVexiActor
    include GitHub::VexiActor
    extend T::Helpers

    sig { params(id: String).returns(RequestIdVexiActor) }
    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    sig { params(request_id: String).void }
    def initialize(request_id)
      @clean_request_id = T.let(request_id.gsub(":", "_"), String)
    end

    sig { returns(String) }
    def id
      @clean_request_id
    end
  end
end
