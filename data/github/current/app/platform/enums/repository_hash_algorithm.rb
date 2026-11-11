# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryHashAlgorithm < Platform::Enums::Base
      docs_category :repos
      description "The hash algorithm used for content within a repository."
      visibility :internal

      value "SHA1", "SHA-1 hashing algorithm.", value: "sha1"
      value "SHA256", "SHA-256 hashing algorithm.", value: "sha256"
    end
  end
end
