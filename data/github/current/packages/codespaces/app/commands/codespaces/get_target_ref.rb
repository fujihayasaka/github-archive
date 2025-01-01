# typed: true
# frozen_string_literal: true

module Codespaces
  class GetTargetRef < Command
    def initialize(repository:, name_or_oid:)
      @repository = repository
      @name_or_oid = name_or_oid
    end

    def perform
      # This will find a branch or tag, returning a branch if it finds both.
      ref = @repository.refs.find(@name_or_oid)
      return ref if ref

      # This will find the ref from a valid SHA, but we have to fetch everything.
      # If we find more than one match, we'll want to ensure a detached HEAD, so don't use any.
      refs = @repository.refs.select { |ref| ref.target_oid == @name_or_oid }
      return refs.first if refs.length == 1

      # This ensures we still return a Git::Ref, but the target_oid is nil unless a SHA found multiple hits above.
      @repository.refs.read(@name_or_oid)
    end
  end
end
