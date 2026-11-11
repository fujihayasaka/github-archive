# typed: strict
# frozen_string_literal: true

module GlobalNavigation
  class GlobalNavigationPayload < BasePayload
    include Search::Blackbird::Features
    include InProductTargeting::TransactionalMessageConcern

    sig { returns(T.nilable(T.any(Symbol, String))) }
    attr_reader :selected_link

    sig { returns(T::Boolean) }
    attr_reader :is_search_page
    alias :is_search_page? :is_search_page

    sig { returns(T.untyped) }
    attr_reader :page_breadcrumb_object

    sig { returns(Site::HeaderView) }
    attr_reader :view

    sig { override.returns(String) }
    def route_id
      "globalNavigationRoute"
    end

    sig do
      params(
        current_user: User,
        view: Site::HeaderView,
        source: String,
        current_copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User)),
        current_repository: T.nilable(Repository),
        current_organization: T.nilable(Organization),
        selected_link: T.nilable(T.any(Symbol, String)),
        page_breadcrumb_object: T.untyped,
        is_search_page: T::Boolean,
      ).void
    end
    def initialize(
      current_user:,
      view:,
      source:,
      current_copilot_user: nil,
      current_repository: nil,
      current_organization: nil,
      selected_link: nil,
      page_breadcrumb_object: nil,
      is_search_page: false
    )
      super(
        current_user: current_user,
        current_copilot_user: current_copilot_user,
        current_repository: current_repository,
        current_organization: current_organization,
        source: source
      )
      @selected_link = selected_link
      @page_breadcrumb_object = page_breadcrumb_object
      @is_search_page = is_search_page
      @view = view
    end

    sig { override.params(context_crumb: T.nilable(ContextRegion::Crumb)).returns(T::Array[String]) }
    def tracking_tags(context_crumb: nil)
      tags = ["source:#{source}"]
      tags << "context_region_type:#{context_crumb.crumb_type}" if context_crumb
      tags
    end

    sig do
      override.params(
        display_switch_account_popover: T::Boolean,
        return_to: T.nilable(String),
        context_crumb: T.nilable(ContextRegion::Crumb),
        path_resolver: T.nilable(Proc),
        params: T.nilable(ActionController::Parameters)
      ).returns(T::Hash[T.untyped, T.untyped])
    end
    def payload(
      display_switch_account_popover: false,
      return_to: nil,
      context_crumb: nil,
      path_resolver: nil,
      params: nil
    )
      GitHub.dogstats.time("global_navigation.payload", tags: tracking_tags) do
        payloads_path_params = payloads_url_params.dup
        payloads_path_params[:return_to] = return_to if return_to.present?

        {
          contextRegion: context_region_payload(context_crumb: context_crumb, path_resolver: path_resolver),
          userMenu: user_menu_payload,
          headerLogo: header_logo_payload,
          notifications: notifications_payload,
          issues: issues_payload,
          pulls: pulls_payload,
          contributedRepos: contributed_repos_payload,
          copilot: copilot_payload,
          search: search_payload(params),
          enterpriseBanner: enterprise_managed_banner_payload,
          globalTransactionalMessage: global_transactional_message_payload(T.must(current_user), self),
          payloadsUrl: global_navigation_payloads_path(**payloads_path_params)
        }
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def user_menu_payload
      GitHub.dogstats.time("global_navigation.user_menu.owner", tags: tracking_tags) do
        {
          owner: {
            login: current_user&.display_login,
            name: current_user&.profile_name,
            avatarUrl: current_user&.primary_avatar_url
          }
        }
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def header_logo_payload
      GitHub.dogstats.time("global_navigation.header_logo", tags: tracking_tags) do
        {
          href: home_path,
          'aria-label': "Homepage #{GitHub.site_heading(enterprise_managed_user: enterprise_managed_user?)}"
        }
      end
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def notifications_payload
      GitHub.dogstats.time("global_navigation.notifications", tags: tracking_tags) do
        {
          indicatorMode: :none,
          websocketChannel: live_update_view_channel(GitHub::WebSocket::Channels.notifications_changed(current_user)),
          fetchIndicatorSrc: notifications_indicator_path,
          fetchIndicatorEnabled: true
        }
      end
    end

    sig { params(params: T.nilable(ActionController::Parameters)).returns(T::Hash[T.untyped, T.untyped]) }
    def search_payload(params)
      GitHub.dogstats.time("global_navigation.search", tags: tracking_tags) do
        {
          show: !hide_search?,
          showCommandPalette: command_palette_enabled?,
          isSearchPage: is_search_page?,
          isJumpToSearch: !blackbird_enabled?,
          fragmentsPath: global_navigation_fragments_path,
          fragmentsParams: search_params_for_header_search(params),
          searchContext: search_context(params)
        }
      end
    end

    sig { params(context_crumb: T.nilable(ContextRegion::Crumb), path_resolver: T.nilable(Proc)).returns(T::Hash[T.untyped, T.untyped]) }
    def context_region_payload(context_crumb: nil, path_resolver: nil)
      return {} unless context_crumb

      GlobalNavigation::ContextRegionPayload.new(
        crumb: context_crumb,
        path_resolver: path_resolver,
        current_user: current_user,
        current_copilot_user: current_copilot_user_v2,
        selected_link: @selected_link,
        source: source
      ).payload
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def enterprise_managed_banner_payload
      if !show_enterprise_managed_header?
        return { show: false }
      end

      GitHub.dogstats.time("global_navigation.enterprise_managed_banner", tags: tracking_tags) do
        {
          show: true,
          href: enterprise_path(enterprise_managed_business),
          businessName: enterprise_managed_business.name,
          isFirstEmuOwner: T.must(current_user).is_first_emu_owner?,
          viewingAsLogin: T.must(current_user).display_login,
          showDataResidency: show_data_residency?,
          dataResidencyRegion: GitHub::Config::Proxima.current_region_label
        }
      end
    end

    private

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def payloads_url_params
      repository = nil
      current_repo_nwo = nil
      org = nil
      user_id = nil

      if current_repository.present? && view.include_repository_scope?
        repository = current_repository&.name
        current_repo_nwo = current_repository&.name_with_display_owner
        if current_repository&.organization_id?
          org = current_repository&.owner&.display_login
          user_id = current_repository&.owner&.display_login
        else
          user_id = current_repository&.owner&.display_login
        end
      elsif current_organization.present?
        org = current_organization&.display_login
        user_id = current_organization&.display_login
      elsif view.include_owner_scope?(viewer: current_user)
        user_id = view.currently_viewed_user.display_login
      end

      { format: :json, repository: repository, current_repo_nwo: current_repo_nwo, org: org, user_id: user_id }.compact
    end

    sig { params(params: T.nilable(ActionController::Parameters)).returns(T::Hash[T.untyped, T.untyped]) }
    def search_params(params)
      scope = ""
      current_repo_name = ""
      current_repo_nwo = ""
      current_repo_org = ""
      user_id = ""
      if current_repository.present? && view.include_repository_scope?
        scope = "repo:#{current_repository&.name_with_display_owner}"
        current_repo_name = current_repository&.name
        current_repo_nwo = current_repository&.name_with_display_owner
        if current_repository&.organization_id?
          current_repo_org = current_repository&.owner&.display_login
          user_id = current_repository&.owner&.display_login
          business = current_repository&.owner&.business
        else
          user_id = current_repository&.owner&.display_login
        end
      elsif current_organization.present?
        scope = "org:#{current_organization&.display_login}"
        current_repo_org = current_organization&.display_login
        user_id = current_organization&.display_login
        business = current_organization&.business
      elsif view.include_owner_scope?(viewer: current_user)
        scope = "owner:#{view.currently_viewed_user.display_login}"
        user_id = view.currently_viewed_user.display_login
      end

      # Despite the name, `unaffiliated_member?` actually checks if the user is any kind of member.
      if current_user.present? && business&.unaffiliated_member?(current_user)
        current_business = business.slug
      end

      {
        params: params,
        scope: scope,
        current_repo_name: current_repo_name,
        current_repo_nwo: current_repo_nwo,
        current_repo_org: current_repo_org,
        user_id: user_id,
        current_business: current_business
      }
    end

    sig { params(params: T.nilable(ActionController::Parameters)).returns(String) }
    def search_params_for_header_search(params)
      return "" unless FeatureFlag.vexi.enabled?(:global_nav_react_blackbird_fragment, current_user, default: false)
      return "" unless params
      search_data = search_params(params)

      serialized_params = []
      serialized_params << "q=#{CGI.escape(params[:q])}" if params[:q].present?
      serialized_params << "scope=#{CGI.escape(search_data[:scope])}" if search_data[:scope].present?
      serialized_params << "current_repo_nwo=#{CGI.escape(search_data[:current_repo_nwo])}" if search_data[:current_repo_nwo].present?
      serialized_params << "repository=#{CGI.escape(search_data[:current_repo_name])}" if search_data[:current_repo_name].present?
      serialized_params << "org=#{CGI.escape(search_data[:current_repo_org])}" if search_data[:current_repo_org].present?
      serialized_params << "user_id=#{CGI.escape(search_data[:user_id])}" if search_data[:user_id].present?
      serialized_params << "is_search_page=true" if is_search_page?
      serialized_params << "business_context=#{CGI.escape(search_data[:current_business])}" if search_data[:current_business].present?

      if command_palette_enabled?
        serialized_params << "command_scope_id=#{CGI.escape(page_breadcrumb_object&.id.to_s)}" if page_breadcrumb_object&.id
        serialized_params << "command_scope_type=#{CGI.escape(page_breadcrumb_object&.class&.name.to_s)}" if page_breadcrumb_object&.class&.name
        serialized_params << "clear_command_scope=true" if params[:clear_command_scope].present?
      end

      serialized_params.join("&")
    end

    sig { params(params: T.nilable(ActionController::Parameters)).returns(T::Hash[T.untyped, T.untyped]) }
    def search_context(params)
      search_data = search_params(params)
      search_data.slice(:scope, :current_repo_name, :current_repo_nwo, :current_repo_org, :user_id, :current_business).filter { |_k, v| v.present? }
    end

    sig { returns(T::Boolean) }
    def command_palette_enabled?
      return false unless logged_in?
      T.must(current_user).command_palette_enabled?
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    memoize def copilot_payload
      GlobalNavigation::CopilotPayload.new(
        current_user: current_user,
        current_copilot_user: current_copilot_user_v2,
        current_repository: current_repository,
        source: source
      ).payload(include_agents_panel: false)
    end

    sig { returns(T::Boolean) }
    memoize def show_data_residency?
      show_enterprise_managed_header? &&
      GitHub.multi_tenant_enterprise? &&
      GitHub::Config::Proxima.current_region_label.present?
    end

    sig { returns(Business) }
    memoize def enterprise_managed_business
      T.must(current_user).enterprise_managed_business
    end

    sig { returns(T::Boolean) }
    memoize def show_enterprise_managed_header?
      return false unless logged_in?
      return false unless T.must(current_user).is_enterprise_managed?
      enterprise_managed_business.present?
    end

    sig { returns(T::Boolean) }
    memoize def global_nav_react_enabled?
      FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)
    end
  end
end
