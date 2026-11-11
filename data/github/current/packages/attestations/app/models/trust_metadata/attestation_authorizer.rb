# typed: true
# frozen_string_literal: true

module TrustMetadata
  class AttestationAuthorizer
    attr_reader :actor
    def initialize(actor)
      @actor = actor
    end

    def can_read_repo?(repo)
      repo.resources.attestations.readable_by?(actor)
    end

    def can_write_repo?(repo)
      repo.resources.attestations.writable_by?(actor)
    end
  end
end
