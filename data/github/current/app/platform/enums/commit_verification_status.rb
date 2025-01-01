# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class CommitVerificationStatus < Platform::Enums::Base
      description "The status of a commit verification"

      value "VERIFIED", "A signed commit is valid and all authors have enabled vigilant mode", value: :verified
      value "PARTIALLY_VERIFIED", "A signed commit is valid and at least one author has enabled vigilant mode", value: :partially_verified
      value "UNVERIFIED", "A commit where the signature cannot be verified", value: :unverified
      value "UNSIGNED", "An unsigned commit", value: :unsigned
    end
  end
end
