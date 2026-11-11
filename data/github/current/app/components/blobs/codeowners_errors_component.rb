# typed: true
# frozen_string_literal: true

module Blobs
  class CodeownersErrorsComponent < ApplicationComponent
    def initialize(blob)
      @blob = blob
    end

    def render?
      is_codeowners_file?
    end

    memoize def errors
      if is_codeowners_file?
        (codeowners_file.errors + owner_errors).sort_by(&:line)
      else
        []
      end
    end

    private

    def owner_errors
      codeowners_file.owner_errors
    end

    def codeowners_file
      return nil unless is_codeowners_file?
      @codeowners_file ||= ::Codeowners::File.new(@blob.data.to_s, owner_resolver: owner_resolver)
    end

    memoize def owner_resolver
      Repository::Codeowners::ActiveRecordOwnerResolver.new(@blob.repository)
    end

    def is_codeowners_file?
      PreferredFile.is_type?(tree_entry: @blob, type: :codeowners)
    end
  end
end
