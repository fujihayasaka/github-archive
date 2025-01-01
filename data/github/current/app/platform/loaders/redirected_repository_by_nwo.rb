# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class RedirectedRepositoryByNwo < Platform::Loader
      def self.load(nwo)
        self.for.load(nwo.downcase)
      end

      def self.load_all(nwos)
        loader = self.for
        Promise.all(nwos.map { |nwo| loader.load(nwo) })
      end

      def fetch(nwos)
        redirects = ::RepositoryRedirect
          .includes(:repository)
          .where(repository_name: nwos)
          .order("repository_redirects.created_at DESC, repository_redirects.id DESC")
          .group_by(&:repository_name)
          .flat_map do |nwo, rrs|
            nwo = nwo.downcase
            repo = rrs.first.repository

            # RepositoryRedirect stores repository_name with the unique nwo in Proxima.
            # For each repository returned, return a record with the unique nwo and
            # a record with the display nwo. That way, if the display value was requested
            # we'll match it, and if the unique value was requested we'll match it.
            # For dotcom, the unique nwo and the display nwo are the same,
            # and there's no issue returning the same entry twice.
            owner_login, name = nwo.split("/")
            [[nwo, repo], ["#{User.to_display_login(owner_login)}/#{name}", repo]]
          end

        redirects.to_h
      end
    end
  end
end
