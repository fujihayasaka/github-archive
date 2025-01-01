# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PublishedRepositoryAdvisoryByGhsa < Platform::Loader
      def self.load(ghsa_id)
        if ghsa_id.blank? || ghsa_id !~ AdvisoryDB.valid_ghsa_id_input_pattern
          return Promise.resolve(nil)
        end

        ghsa_id = AdvisoryDB.canonical_case_for_ghsa_id(ghsa_id)
        self.for.load(ghsa_id)
      end

      def self.load_all(ghsa_ids)
        Promise.all(ghsa_ids.map(&method(:load)))
      end

      def fetch(ghsa_ids)
        ::RepositoryAdvisory.where(state: "published", ghsa_id: ghsa_ids).
                             preload(:repository).
                             preload(:vulnerability).
                             index_by(&:ghsa_id)
      end
    end
  end
end
