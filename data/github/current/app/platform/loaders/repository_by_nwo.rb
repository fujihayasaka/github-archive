# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryByNwo < Platform::Loader
      def self.load(name_with_owner)
        self.for.load(name_with_owner.downcase)
      end

      def fetch(names_with_owners)
        ::Repository.with_names_with_owners(names_with_owners).each_with_object({}) do |repo, hash|
          # return both the suffixed value and the unsuffixed value to be matched on the lookup
          hash[repo.name_with_owner.downcase] = repo # rubocop:disable GitHub/DoNotAllowNameWithOwner
          hash[repo.name_with_display_owner.downcase] ||= repo
        end
      end
    end
  end
end
