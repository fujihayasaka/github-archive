# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # Determines the actual name that would be used when creating a fork with the given candidate name
    #
    # If the new owner doesn't have a repository using this name, then the name is fine.
    # If the new owner already has a repository using this name, tack on a "-1"
    # (unless the name already ends in a "-" and digits), and then keep incrementing
    # until you find something that isn't taken.
    class NewForkName < Platform::Loader
      FORK_NAME_SUFFIX_PATTERN = /-\d+\z/

      def self.load(owner, candidate_name)
        self.for(candidate_name).load(owner)
      end

      def initialize(candidate_name)
        @candidate_name = candidate_name.dup
      end

      private

      attr_reader :candidate_name

      def fetch(owners)
        names_by_owner_ids = fetch_names_by_owner(owners)
        find_candidates(owners, names_by_owner_ids)
      end

      def find_candidates(owners, names_by_owner_ids)
        owners.each_with_object({}) do |owner, hash|
          names = names_by_owner_ids[owner.id]

          owner_candidate_name = candidate_name

          if names&.include?(owner_candidate_name.downcase)
            if owner_candidate_name !~ FORK_NAME_SUFFIX_PATTERN
              owner_candidate_name = owner_candidate_name + "-1"
            end
            owner_candidate_name.succ! while names.include?(owner_candidate_name.downcase)
          end

          hash[owner] = owner_candidate_name
        end
      end

      def fetch_names_by_owner(owners)
        root_name = candidate_name.sub(FORK_NAME_SUFFIX_PATTERN, "")
        similar_names = Repository.active.where(owner: owners).
          where("name like ?", "#{root_name}%").
          pluck(:owner_id, :name)

        # disabled linters below because they are lookups and comparisons not shown to customer
        retired_similar_names = RetiredNamespace.
          where(owner_login: owners.map(&:login)). # rubocop:disable GitHub/DoNotAllowLogin
          where("name like ?", "#{root_name}%").
          pluck(:owner_login, :name)

        owners_by_login = owners.index_by { |owner| owner.login.downcase } # rubocop:disable GitHub/DoNotAllowLogin

        retired_similar_names = retired_similar_names.map { |login, name| [owners_by_login[login].id, name] }

        coalesce_names(similar_names, retired_similar_names)
      end

      def coalesce_names(similar_names, retired_similar_names)
        names_by_owner_ids = Hash.new { |h, k| h[k] = Set.new }

        coalesce = lambda do |(owner_id, name)|
          names = names_by_owner_ids[owner_id]
          names << name.downcase
        end

        similar_names.each(&coalesce)
        retired_similar_names.each(&coalesce)

        names_by_owner_ids
      end
    end
  end
end
