# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class JumpToPageNavigationProvider < PrefetchedProvider

      # Order here is important. Higher order is implicitly a higher priority.
      PAGE_NAVIGATORS = [
        PageNavigators::GlobalPageNavigator,
        PageNavigators::UserPageNavigator,
        PageNavigators::OrgPageNavigator,
        PageNavigators::RepoPageNavigator,
      ]

      def search(query)
        items = T.let([], T::Array[Result])

        PAGE_NAVIGATORS.each do |page_navigator_class|
          items += page_navigator_class.items(context)
        end

        items
      end
    end
  end
end
