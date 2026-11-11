# typed: strict
# frozen_string_literal: true

# This is the public interface for the SBOM generation service that Dependency Graph provides to the monolith.
#
# NOTE: At time of writing, much of the code used by these interfaces is public and can be called directly but this
# is an initial effort at establishing a package interface so we can make them private in the near future.
#   see: https://github.com/github/dependency-graph/pull/5751
#
module DependencyGraph
  module SBOM
    class SBOMFile < T::Struct
      prop :filename, String
      prop :contents, String
    end

    class SBOMRequestError < StandardError; end # Raised for any remote service exception
    class SBOMTimeoutError < StandardError; end # Raised on client-side timeout

    # TODO: Verify if we always return a nilable string from both clients
    sig { params(repository: Repository, ghes: T::Boolean).returns(SBOMFile) }
    def self.get_sbom_for_repository(repository, ghes: false)
      Sbomer.new(repository, ghes:).get_sbom
    end
  end
end
