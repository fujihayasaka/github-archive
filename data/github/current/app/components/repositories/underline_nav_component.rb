# typed: true
# frozen_string_literal: true

module Repositories
  class UnderlineNavComponent < ApplicationComponent
    include TreeHelper
    attr_reader :current_repository, :user_can_write_wiki

    def initialize(repository:, selected_link: nil, display_variant: :none, user_can_write_wiki: nil)
      @current_repository = repository
      @selected_link = selected_link
      @display_variant = display_variant
      @user_can_write_wiki = user_can_write_wiki
    end

    def repository_offline?
      helpers.repository_offline?
    end

    def padding_classes
      return [3, nil, 4, 5] if @display_variant == :padded

      []
    end

    def tabs
      if FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)
        # We directly include the security tab in the React payload, no need to pass in the security_counter proc
        navigation_tabs.tabs
      else
        # The Rails navigation has a lazy-loaded security tab/count
        navigation_tabs.links(security_counter: -> () {
          render(Primer::Alpha::IncludeFragment.new(src: repository_security_overall_count_path(current_repository.owner, current_repository.name), accept: "text/fragment+html"))
        })
      end
    end

    private

    memoize def navigation_tabs
      Repository::NavigationTabs.new(
        repository: current_repository,
        current_user: helpers.current_user,
        user_can_write_wiki: user_can_write_wiki,
        current_branch_or_tag_name: current_branch_or_tag_name_for_urls
      )
    end
  end
end
