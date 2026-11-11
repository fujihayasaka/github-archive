# typed: strict
# frozen_string_literal: true

module Repos
  module CodeViewHeader
    sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
    def self.enabled?(current_user)
      FeatureFlag.vexi.enabled?(:ui_route_code_view, current_user, default: false) || FeatureFlag.vexi.enabled?(:code_view_react_header, current_user, default: false)
    end

    class CodeViewHeader
      include UrlHelpers
      include UrlHelper
      include GitHub::RouteHelpers
      include EscapeHelper

      sig do
        params(
          view_model: T.nilable(Files::OverviewView),
          current_user: T.nilable(User),
          current_repository: Repository,
        ).void
      end
      def initialize(view_model:, current_user:, current_repository:)
        @view_model = view_model
        @current_user = current_user
        @current_repository = current_repository
      end

      sig { returns(HeaderPayload) }
      def header_payload
        owner = @current_repository.owner
        repo = @current_repository

        HeaderPayload.new(
          repo: RepoIdentity.new(
            ownerAvatarUrl: owner&.primary_avatar_url(60) || "",
            ownerId: owner&.id,
            isPrivate: repo.private?,
            isTemplate: repo.template?,
            isFork: repo.fork?,
            isMirror: repo.mirror?,
            isArchived: repo.archived?,
            visibilityLabel: visibility_label(repo),
            parentRepo: parent_repo_info(repo),
            mirrorUrl: mirror_url(repo),
            templateSource: template_source_info(repo),
            license: license_info(repo),
            isAdvisoryWorkspace: repo.advisory_workspace?,
          ),
          advisoryInfo: advisory_info(repo),
          star: StarData.new(
            viewerHasStarred: viewer_has_starred?(repo),
            canStar: can_star?(repo),
          ),
          fork: fork_data(repo),
          pin: PinData.new(
            canPin: can_pin?(repo, owner),
            isPinned: is_pinned?(repo, owner),
            isOrgOwned: owner&.organization? || false,
            orgPinData: organization_pin_data(repo, owner),
            pinItemsRemaining: pin_items_remaining(owner),
          ),
          watch: WatchButtonData.new(
            canWatch: can_watch?(repo),
            watchData: build_watch_data(repo, owner),
          ),
          viewer: ViewerState.new(
            isLoggedIn: @current_user.present?,
            isSiteAdmin: @current_user&.site_admin? || false,
            emuContributionBlocked: emu_contribution_blocked?(repo),
          ),
          showSponsorButton: show_sponsor_button?(repo),
          showTemplateButton: show_template_button?(repo),
          showDemoNotification: show_demo_notification?(repo),
        )
      end

      sig { returns(UserListsPayload) }
      def user_lists_payload
        return UserListsPayload.new(
          lists: [],
          createPath: nil,
          repositoryId: @current_repository.id.to_s,
          repoIsOnAnyList: false,
          listsContainingRepoCount: 0,
          canCreateList: false,
        ) unless @current_user

        user_lists = @current_user.lists.order(:name).limit(UserList::MAX_PER_USER)
        lists_applied = UserList.applied_to(user_id: @current_user.id, repository_ids: [@current_repository.id])
        applied_list_ids = lists_applied.containing(@current_repository.id).map(&:id).to_set

        lists = user_lists.map do |list|
          UserListItem.new(
            id: list.id,
            name: list.name,
            description: list.description,
            repoIncluded: applied_list_ids.include?(list.id),
          )
        end

        containing_count = lists.count(&:repoIncluded)

        UserListsPayload.new(
          lists: lists,
          createPath: user_lists_path(@current_user),
          repositoryId: @current_repository.id.to_s,
          repoIsOnAnyList: containing_count > 0,
          listsContainingRepoCount: containing_count,
          canCreateList: user_lists.size < UserList::MAX_PER_USER,
        )
      end

      private

      sig { params(repo: Repository).returns(String) }
      def visibility_label(repo)
        RepositoriesTypeHelper.type(
          visibility: repo.visibility,
          mirror: repo.mirror?,
          archived: repo.archived?,
          template: repo.template?,
        )
      end

      sig { params(repo: Repository).returns(T.nilable(ParentRepoInfo)) }
      def parent_repo_info(repo)
        parent = repo.parent
        return nil unless repo.fork? && parent

        ParentRepoInfo.new(
          ownerLogin: parent.owner&.display_login || "",
          name: parent.name,
          url: repository_path(parent),
        )
      end

      sig { params(repo: Repository).returns(T.nilable(String)) }
      def mirror_url(repo)
        return nil unless repo.mirror?

        repo.mirror&.url
      end

      sig { params(repo: Repository).returns(T.nilable(ParentRepoInfo)) }
      def template_source_info(repo)
        source = repo.template_repository
        return nil unless source

        ParentRepoInfo.new(
          ownerLogin: source.owner&.display_login || "",
          name: source.name,
          url: repository_path(source),
        )
      end

      sig { params(repo: Repository).returns(T.nilable(AdvisoryInfo)) }
      def advisory_info(repo)
        return nil unless repo.advisory_workspace?

        advisory = repo.parent_advisory
        return nil unless advisory

        upstream = repo.parent_advisory_repository
        return nil unless upstream

        AdvisoryInfo.new(
          ghsaId: advisory.ghsa_id,
          url: gh_repository_advisory_path(advisory),
          parentRepo: ParentRepoInfo.new(
            ownerLogin: upstream.owner&.display_login || "",
            name: upstream.name,
            url: repository_path(upstream),
          ),
        )
      end

      sig { params(repo: Repository, owner: T.nilable(User)).returns(WatchData) }
      def build_watch_data(repo, owner)
        subscription = unwrap_subscription_status(repo)
        sub_type = compute_subscription_type(subscription)
        show_labels = show_label_subscriptions?(repo)
        subscribed_labels = resilient_section { show_labels && @current_user ? repo.subscribed_labels(@current_user) : [] } || []
        subscribed_label_ids = subscribed_labels.map(&:global_relay_id)

        WatchData.new(
          repositoryId: repo.id.to_s,
          repositoryName: repo.full_name,
          watchersCount: repo.watchers_count,
          subscriptionType: sub_type || "none",
          subscribableThreadTypes: build_subscribable_thread_types(repo, subscription),
          showLabelSubscriptions: show_labels,
          subscribedLabels: subscribed_labels.map do |label|
            {
              id: label.global_relay_id,
              name: label.name,
              nameHTML: label.name_html,
              color: label.color,
              description: label.description,
              subscribed: true,
            }
          end,
        )
      end

      sig { params(repo: Repository).returns(T.nilable(Newsies::Subscription)) }
      def unwrap_subscription_status(repo)
        return nil unless @current_user

        Notifications::Subscriptions.list_subscription_status(@current_user, repo)
      end

      sig { params(status: T.nilable(Newsies::Subscription)).returns(T.nilable(String)) }
      def compute_subscription_type(status)
        return nil unless status

        if status.subscribed?
          "watching"
        elsif status.thread_types.any?
          "custom"
        elsif status.participation_only?
          "none"
        elsif status.ignored?
          "ignoring"
        end
      end

      sig { params(repo: Repository, status: T.nilable(Newsies::Subscription)).returns(T::Array[ThreadType]) }
      def build_subscribable_thread_types(repo, status)
        types = T.let([], T::Array[ThreadType])

        types << ThreadType.new(name: "Issue", enabled: repo.has_issues, subscribed: thread_type_subscribed?(status, "Issue"))
        types << ThreadType.new(name: "PullRequest", enabled: repo.has_pull_requests?, subscribed: thread_type_subscribed?(status, "PullRequest"))
        types << ThreadType.new(name: "Release", enabled: true, subscribed: thread_type_subscribed?(status, "Release"))

        if repo.eligible_for_discussions?
          types << ThreadType.new(name: "Discussion", enabled: repo.discussions_active?, subscribed: thread_type_subscribed?(status, "Discussion"))
        end

        types << ThreadType.new(name: "SecurityAlert", enabled: true, subscribed: thread_type_subscribed?(status, "SecurityAlert"))

        types
      end

      sig { params(status: T.nilable(Newsies::Subscription), thread_type: String).returns(T::Boolean) }
      def thread_type_subscribed?(status, thread_type)
        return false unless status

        !status.ignored? && status.thread_types.include?(thread_type)
      end

      sig { params(repo: Repository, show_labels: T::Boolean).returns(T::Array[Integer]) }
      def build_subscribed_label_ids(repo, show_labels)
        return [] unless show_labels && @current_user

        repo.subscribed_label_ids(@current_user)
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def show_label_subscriptions?(repo)
        return false unless @current_user

        Notifyd::Flags.new(@current_user).label_subscriptions?(repo)
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def can_star?(repo)
        return false unless @current_user
        return false if repo.archived?
        return false if emu_contribution_blocked?(repo)

        true
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def emu_contribution_blocked?(repo)
        return false unless @current_user&.is_enterprise_managed?

        repo_business = repo.enterprise_managed_business
        return false unless repo_business

        @current_user.enterprise_managed_business != repo_business
      end

      sig { params(repo: Repository).returns(ForkData) }
      def fork_data(repo)
        error = forkability_error(repo)
        ForkData.new(
          canFork: error.nil?,
          forkabilityError: error,
        )
      end

      sig { params(repo: Repository).returns(T.nilable(String)) }
      def forkability_error(repo)
        return "not_logged_in" unless @current_user

        if repo.forking_disabled?
          "forking_disabled"
        elsif repo.locked?
          "repo_locked"
        elsif repo.disabled?(viewer: @current_user)
          "repo_disabled"
        elsif repo.access.dmca?
          "dmca"
        elsif @current_user == repo.owner && @current_user.organizations.empty?
          "nowhere_to_fork"
        elsif repo.probably_empty?
          "repo_empty"
        elsif emu_contribution_blocked?(repo)
          "emu_blocked"
        end
      rescue GitRPC::ConnectionError => e
        Failbot.report!(e)
        "repo_offline"
      rescue => e
        Failbot.report!(e)
        "unavailable"
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def can_watch?(repo)
        return false unless @current_user
        return false if emu_contribution_blocked?(repo)

        true
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def viewer_has_starred?(repo)
        return false unless @current_user

        Stars.domain.repo_starred_by_user?(repo.id, @current_user.id)
      end

      sig { params(repo: Repository, owner: T.nilable(User)).returns(T::Boolean) }
      def can_pin?(repo, owner)
        return false unless @current_user
        owner&.can_pin_profile_items?(@current_user) || false
      end

      sig { params(repo: Repository, owner: T.nilable(User)).returns(T::Boolean) }
      def is_pinned?(repo, owner)
        return false unless owner
        owner.pinned_repository?(repo)
      end

      sig { params(owner: T.nilable(User)).returns(Integer) }
      def pin_items_remaining(owner)
        return 0 unless owner
        owner.pinned_items_remaining
      end

      sig { params(repo: Repository, owner: T.nilable(User)).returns(T.nilable(OrgPinData)) }
      def organization_pin_data(repo, owner)
        return nil unless owner&.organization?
        return nil unless @current_user

        can_pin_profile_items = owner.can_pin_profile_items?(@current_user)
        can_pin_publicly = T.let(!!(can_pin_profile_items && repo.public?), T::Boolean)
        can_pin_internally = T.let(!!can_pin_profile_items, T::Boolean)
        can_pin_to_viewer_profile = T.let(!!(repo.public? && repo.contributor_of_any_kind?(@current_user)), T::Boolean)
        is_pinned_publicly = T.let(!!owner.pinned_repository?(repo), T::Boolean)
        is_pinned_internally = T.let(!!owner.pinned_repository?(repo, internal_view: true), T::Boolean)
        is_pinned_to_viewer_profile = T.let(!!@current_user.pinned_repository?(repo), T::Boolean)

        return nil unless [
          can_pin_publicly,
          can_pin_internally,
          can_pin_to_viewer_profile,
          is_pinned_publicly,
          is_pinned_internally,
          is_pinned_to_viewer_profile,
        ].any?

        OrgPinData.new(
          canPinPublicly: can_pin_publicly,
          canPinInternally: can_pin_internally,
          canPinToViewerProfile: can_pin_to_viewer_profile,
          isPinnedPublicly: is_pinned_publicly,
          isPinnedInternally: is_pinned_internally,
          isPinnedToViewerProfile: is_pinned_to_viewer_profile,
          publicPinsRemaining: owner.pinned_items_remaining,
          internalPinsRemaining: owner.pinned_items_remaining(internal_view: true),
          viewerPinsRemaining: @current_user.pinned_items_remaining,
        )
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def show_sponsor_button?(repo)
        return false unless GitHub.sponsors_enabled?
        return false if @current_user&.has_any_trade_restrictions?

        repo.show_sponsor_button?
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def show_template_button?(repo)
        repo.template? && @current_user.present?
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def show_demo_notification?(repo)
        org = repo.organization
        return false if org.nil? || @current_user.nil?

        org.adminable_by?(@current_user) && demo_repo?(repo) && !user_dismissed_demo_notification?(repo, @current_user)
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def demo_repo?(repo)
        repo.created_for_demo_by_gh? || OrganizationOnboard::DemoRepository.where(repository: repo).exists?
      end

      sig { params(repo: Repository, user: User).returns(T::Boolean) }
      def user_dismissed_demo_notification?(repo, user)
        return true unless User::NoticesDependency::ORGANIZATION_NOTICES.key?(:demo_repository_notification)
        notice = User::NoticesDependency::ORGANIZATION_NOTICES[:demo_repository_notification]
        user.dismissed_organization_notice?(notice, repo.organization, for_whole_org: true)
      end

      sig { params(repo: Repository).returns(T.nilable(LicenseInfo)) }
      def license_info(repo)
        license = repo.license
        return nil unless license
        LicenseInfo.new(
          spdxId: license.spdx_id,
          name: license.name,
        )
      end

      # Wraps a section payload call so that any error returns nil instead of
      # crashing the entire unified response. Mirrors the sidebar's
      # `render_nothing_on_error` behaviour.
      sig { type_parameters(:T).params(block: T.proc.returns(T.type_parameter(:T))).returns(T.nilable(T.type_parameter(:T))) }
      def resilient_section(&block)
        block.call
      rescue GitHub::DatabaseQueryDisabler::DatabaseDisabledError
        nil
      rescue StandardError => e
        Failbot.report(e)
        nil
      end
    end

    ## Payload Structs

    class ThreadType < T::Struct
      const :name, String
      const :enabled, T::Boolean
      const :subscribed, T::Boolean
    end

    class WatchData < T::Struct
      const :repositoryId, String
      const :repositoryName, String
      const :watchersCount, Integer
      const :subscriptionType, String
      const :subscribableThreadTypes, T::Array[ThreadType]
      const :showLabelSubscriptions, T::Boolean
      const :subscribedLabels, T::Array[T::Hash[Symbol, T.untyped]]
    end

    class ParentRepoInfo < T::Struct
      const :ownerLogin, String
      const :name, String
      const :url, String
    end

    class AdvisoryInfo < T::Struct
      const :ghsaId, String
      const :url, String
      const :parentRepo, ParentRepoInfo
    end

    class LicenseInfo < T::Struct
      const :spdxId, T.nilable(String)
      const :name, String
    end

    class OrgPinData < T::Struct
      const :canPinPublicly, T::Boolean
      const :canPinInternally, T::Boolean
      const :canPinToViewerProfile, T::Boolean
      const :isPinnedPublicly, T::Boolean
      const :isPinnedInternally, T::Boolean
      const :isPinnedToViewerProfile, T::Boolean
      const :publicPinsRemaining, Integer
      const :internalPinsRemaining, Integer
      const :viewerPinsRemaining, Integer
    end

    # --- Grouped header-specific structs ---

    class RepoIdentity < T::Struct
      const :ownerAvatarUrl, String
      const :ownerId, T.nilable(Integer)
      const :isPrivate, T::Boolean
      const :isTemplate, T::Boolean
      const :isFork, T::Boolean
      const :isMirror, T::Boolean
      const :isArchived, T::Boolean
      const :visibilityLabel, String
      const :parentRepo, T.nilable(ParentRepoInfo)
      const :mirrorUrl, T.nilable(String)
      const :templateSource, T.nilable(ParentRepoInfo)
      const :license, T.nilable(LicenseInfo)
      const :isAdvisoryWorkspace, T::Boolean
    end

    class StarData < T::Struct
      const :viewerHasStarred, T::Boolean
      const :canStar, T::Boolean
    end

    class ForkData < T::Struct
      const :canFork, T::Boolean
      const :forkabilityError, T.nilable(String)
    end

    class PinData < T::Struct
      const :canPin, T::Boolean
      const :isPinned, T::Boolean
      const :isOrgOwned, T::Boolean
      const :orgPinData, T.nilable(OrgPinData)
      const :pinItemsRemaining, Integer
    end

    class WatchButtonData < T::Struct
      const :canWatch, T::Boolean
      const :watchData, WatchData
    end

    class ViewerState < T::Struct
      const :isLoggedIn, T::Boolean
      const :isSiteAdmin, T::Boolean
      const :emuContributionBlocked, T::Boolean
    end

    class HeaderPayload < T::Struct
      const :repo, RepoIdentity
      const :advisoryInfo, T.nilable(AdvisoryInfo)
      const :star, StarData
      const :fork, ForkData
      const :pin, PinData
      const :watch, WatchButtonData
      const :viewer, ViewerState
      const :showSponsorButton, T::Boolean
      const :showTemplateButton, T::Boolean
      const :showDemoNotification, T::Boolean
    end

    # --- User lists (unchanged) ---

    class UserListItem < T::Struct
      const :id, Integer
      const :name, String
      const :description, T.nilable(String)
      const :repoIncluded, T::Boolean
    end

    class UserListsPayload < T::Struct
      const :lists, T::Array[UserListItem]
      const :createPath, T.nilable(String)
      const :repositoryId, String
      const :repoIsOnAnyList, T::Boolean
      const :listsContainingRepoCount, Integer
      const :canCreateList, T::Boolean
    end
  end
end
