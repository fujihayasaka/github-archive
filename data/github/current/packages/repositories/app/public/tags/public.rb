# typed: strict
# frozen_string_literal: true

module Tags
  module Public
    class << self
      extend T::Sig

      # Retrieve tag ref mappings for a repository in chronological
      # order. The ordering is based on the creation date of the peeled commit
      # object the tag ref points to.
      #
      # Note that the collection returned only includes tag refs which resolve
      # to a commit object. Tag refs that resolve to any other type are
      # excluded.
      sig { params(repository: ::Repository, pattern: T.nilable(String)).returns(T::Array[ITag]) }
      def sorted_for(repository:, pattern: nil)
        if pattern
          # * is not a valid tag name character, so we can safely remove it to prevent globbing issues
          pattern = pattern.gsub("*", "")
        end

        response = repository.spokes_api.list_references_with_details(globs: ["refs/tags/**/*#{pattern}*/**"]).data
        refs = response.refs.map do |ref|
          [ref.reference.name, ref.target_id.id, ref.peeled_id.id, ref.commit_time&.timestamp&.to_time.to_i]
        end
        sort_refs!(refs)
        refs.map { |ref| ref[0..2] }
      end

      private

      # Sorts refs by nearest day of creation, then semver, then second of creation
      sig { params(refs: T::Array[[String, String, String, Integer]]).returns(T::Array[[String, String, String, Integer]]) }
      def sort_refs!(refs)
        refs.sort! do |a, b|
          same_day = (a[3] / 86400) <=> (b[3] / 86400)
          if !same_day.zero?
            same_day
          else
            semver = VersionSorter.compare(a[0], b[0]) <=> 0
            semver.zero? ? a[3] <=> b[3] : semver
          end
        end
      end
    end
  end
end
