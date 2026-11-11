# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # Loads Bot records by login (slug), handling both formats:
    # - "my-app" (just the slug)
    # - "my-app[bot]" (slug with [bot] suffix)
    class BotByLogin < Platform::Loader
      def self.load(login)
        return Promise.resolve(nil) if login.blank?

        self.for.load(login)
      end

      def fetch(logins)
        # Normalize logins by stripping [bot] suffix to get slugs
        slugs_by_login = logins.index_with { |login| login.chomp(Bot::LOGIN_SUFFIX) }

        # Load integrations by slug and build a mapping
        integrations = Integration.where(slug: slugs_by_login.values).includes(:bot).index_by(&:slug)

        # Map each login to its bot
        logins.index_with do |login|
          slug = slugs_by_login[login]
          integrations[slug]&.bot || integrations[slug&.downcase]&.bot
        end
      end
    end
  end
end
