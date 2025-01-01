# typed: strict
# frozen_string_literal: true

class VerifiedCommit < ApplicationRecord::Domain::Commits
  self.primary_key = :oid

  serialize :oid, coder: GitHub::Hex
end
