# typed: strict
# frozen_string_literal: true

module Releases
  module Public
    module Helper
      extend T::Sig

      # Public: Find or build a release for the given tag.
      sig { params(repository: ::Repository, tag: String, include_drafts: T::Boolean).returns(T.nilable(IRelease)) }
      def self.load_or_build_by_tag(repository, tag, include_drafts: false)
        return unless id = repository.id

        release = Public.load_by_tag(id, tag, include_drafts: include_drafts)

        release || Public.build_from_tag(repository, tag)
      end
    end
  end
end
