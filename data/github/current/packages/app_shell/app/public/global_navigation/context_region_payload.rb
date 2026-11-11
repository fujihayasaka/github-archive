# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class ContextRegionPayload < BasePayload
    sig { returns(ContextRegion::Crumb) }
    attr_reader :crumb

    sig { returns(T.nilable(Proc)) }
    attr_reader :path_resolver

    sig { returns(T.nilable(T.any(Symbol, String))) }
    attr_reader :selected_link

    sig { override.returns(String) }
    def route_id
      "contextRegionRoute"
    end

    sig do
      params(
        crumb: ContextRegion::Crumb,
        source: String,
        current_user: T.nilable(User),
        current_copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User)),
        current_repository: T.nilable(Repository),
        current_organization: T.nilable(Organization),
        path_resolver: T.nilable(Proc),
        selected_link: T.nilable(T.any(Symbol, String))
      ).void
    end
    def initialize(
      crumb:,
      source:,
      current_user: nil,
      current_copilot_user: nil,
      current_repository: nil,
      current_organization: nil,
      path_resolver: nil,
      selected_link: nil
    )
      super(
        current_user: current_user,
        current_copilot_user: current_copilot_user,
        current_repository: current_repository,
        current_organization: current_organization,
        source: source
      )
      @crumb = T.let(crumb, ContextRegion::Crumb)
      @path_resolver = T.let(path_resolver, T.nilable(Proc))
      @selected_link = T.let(selected_link, T.nilable(T.any(Symbol, String)))
    end

    sig { override.returns(T::Array[String]) }
    memoize def tracking_tags
      ["crumb_type:#{crumb.crumb_type}", "source:#{source}"]
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      GitHub.dogstats.time("global_navigation.context_region", tags: tracking_tags) do
        tab_payload = GitHub.dogstats.time("global_navigation.context_region.local_navigation", tags: tracking_tags) do
          crumb.tab_payload(user: current_user, current_copilot_user: current_copilot_user_v2)
        end

        {
          crumbs: crumb.crumbs.map { |c| crumb_to_hash(c) },
          localNavigation: tab_payload ? tab_payload.tabs : [],
          localNavigationUpdateChannel: tab_payload&.update_channel,
          selectedLink: selected_link,
        }
      end
    end

    private

    sig { params(crumb_entry: ContextRegion::Crumb).returns(T::Hash[Symbol, T.untyped]) }
    def crumb_to_hash(crumb_entry)
      crumb_hash = crumb_entry.to_h

      if path_resolver && !crumb_hash[:href] && crumb_entry.path_name
        crumb_hash[:href] = T.must(path_resolver).call(crumb_entry.path_name, crumb_entry.path_args)
      end

      crumb_hash
    end
  end
end
