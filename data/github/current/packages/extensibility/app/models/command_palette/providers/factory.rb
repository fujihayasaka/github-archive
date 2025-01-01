# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class Factory
      # Provider order matters when more than 1 provider reports items
      # with the same level of priority.
      PROVIDERS = [
        CommandsProvider,
        JumpToPageNavigationProvider,
        IssuesProvider,
        JumpToProvider,
        JumpToMembersOnlyProvider,
        JumpToMembersOnlyPrefetchedProvider,
        FilesProvider,
        DiscussionsProvider,
        ProjectsProvider,
        RecentIssuesProvider,
        TeamsProvider,
        NameWithOwnerRepositoryProvider,
      ].to_h { |provider| [provider.factory_identifier, provider] }

      # Factory method
      def self.build(factory_identifier, context)
        provider_class = PROVIDERS[factory_identifier]

        if provider_class&.enabled?(context)
          provider_class.new(context)
        end
      end
    end
  end
end
