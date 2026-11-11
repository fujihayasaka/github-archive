# typed: true
# frozen_string_literal: true

module Repos
  module DataRouterDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    include GitHub::Memoizer
    include BranchesHelper
    include RepositoriesHelper
    include Repos::TreePayloadHelper
    include CopilotInfoHelper
    include DesktopHelper

    abstract!

    sig { abstract.returns(T.untyped) }
    def current_user; end

    requires_ancestor { AbstractRepositoryController }

    EMPTY_FILE_TREE = [{ "": { items: [], totalCount: 0 } }, 0, []].freeze

    def layout_route_payload
      GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: layout"]) do
        upload_policy_path = upload_policy_path("assets")

        # When fetched by the UI service via the /_layout endpoint, the request URL does not
        # include the file path or ref. Accept them as query params so the payload is correct.
        effective_path = path_string.presence || params[:currentPath].presence

        payload_data = {
          repo: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          currentUser: Repos::ReactPayload.current_user_payload(current_user),
          uploadToken: authenticity_token_for(upload_policy_path, method: :post),
          allShortcutsEnabled: all_shortcuts_enabled?,
          treeExpanded: tree_expanded?,
          path: effective_path || "/",
          symbolsExpanded: symbols_expanded?,
          refInfo: {
            name: tree_name,
            listCacheKey: ref_list_cache_key,
            canEdit: false,
            currentOid: commit_sha,
          },
          helpUrl: GitHub.help_url,
          findFileWorkerPath: find_file_worker_path,
          findInFileWorkerPath: find_in_file_worker_path,
          githubDevUrl: github_dev_enabled?(**referrer_page_route_context) ? GitHub.codespaces_serverless_url : nil,
        }
        payload_data[:repoState] = repo_state_payload if repo_state_payload.present?
        CodeViewPayloads::LayoutRoutePayload.new(payload_data)
      end
    end

    # State-specific payload for the current repository. Currently populated
    # only for empty repos so the React empty layout can render onboarding
    # prompts, clone URLs, and the mirroring-in-progress state without bloating
    # the top-level layout payload (or the shared `repo` payload) for every
    # other code-view request.
    #
    # Shape: `{ state: <state-name>, data: { ...state-specific keys } }` so
    # future states (e.g. archived, locked) can carry a different `data` shape
    # under the same envelope.
    memoize def repo_state_payload
      return nil unless empty_repo?

      {
        state: "empty",
        data: {
          isMirror: current_repository.mirror?,
          onboardingPrompts: empty_repo_onboarding_prompts_payload,
          httpUrl: current_repository.http_url,
          sshUrl: current_repository.ssh_url,
          desktopUrl: app_clone_url(current_repository),
        }.compact,
      }
    rescue StandardError
      nil
    end

    memoize def empty_repo_onboarding_prompts_payload
      return nil unless empty_repo?
      return nil unless current_user_can_push?
      return nil if current_repository.parent_id?

      Repositories::EmptyRepo::OnboardingPrompts.new(
        repository: current_repository,
        current_user: current_user,
        user_can_push: current_user_can_push?,
        copilot_user: current_copilot_user,
      ).to_payload
    rescue StandardError
      nil
    end

    def codeview_sidebar_about_payload(view:)
      GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: codeview_sidebar_about"]) do
        sidebar = Repos::CodeViewSidebar::CodeViewSidebar.new(
          view_model: view,
          current_user: current_user,
          current_repository: current_repository,
        )
        sidebar_data = sidebar.about_payload.serialize

        unless Repos::CodeViewHeader.enabled?(current_user)
          return CodeViewPayloads::OverviewSidebarAboutPayload.new(sidebar_data)
        end

        header = Repos::CodeViewHeader::CodeViewHeader.new(
          view_model: view,
          current_user: current_user,
          current_repository: current_repository,
        )

        header_data = header.header_payload.serialize
        CodeViewPayloads::OverviewSidebarAboutPayload.new(sidebar_data.merge(header_data))
      end
    end

    def file_tree_layout_payload(error: false)
      GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: file_tree_layout"]) do
        file_tree, file_tree_processing_time, folders_to_fetch = calculate_file_tree(error: error)

        CodeViewPayloads::FileTreeLayoutRoutePayload.new({
          fileTree: file_tree,
          fileTreeProcessingTime: file_tree_processing_time,
          foldersToFetch: folders_to_fetch,
        })
      end
    end

    def file_tree_payload(branch:, start:, stop:)
      GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: file_tree"]) do
        file_tree, file_tree_processing_time, folders_to_fetch = begin
          ascend_tree(
            path: RepositoryPath.new(start),
            stop_path: stop,
            include_current: true,
            branch_name: branch
          )
        rescue GitRPC::NoSuchPath
          EMPTY_FILE_TREE
        end

        CodeViewPayloads::FileTreePayload.new({
          fileTree: file_tree,
          fileTreeProcessingTime: file_tree_processing_time,
          foldersToFetch: folders_to_fetch,
        })
      end
    end

    def overview_header_partial(repo:, cap_view_filter:, view:)
      GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: overview_header"]) do
        render_rails_partial("repository/overview_header", locals: {
          repository: repo,
          partial_tags: [],
          cap_view_filter: cap_view_filter,
          view: view,
        })
      end
    end

    def overview_sidebar_partial(commit:, view:)
      GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: overview_sidebar"]) do
        render_rails_partial("repository/overview_sidebar", locals: {
          commit: commit,
          view: view,
          skip_margin: true,
        })
      end
    end

    def calculate_file_tree(error: false)
      return EMPTY_FILE_TREE if empty_repo?

      path = path_for_file_tree

      return ascend_tree(path: path, include_current: true) if !error

      # Best-attempt to get the file tree in case of 404s and 500s from the blob.
      file_tree, file_tree_processing_time, folders_to_fetch = if path.empty?
        EMPTY_FILE_TREE
      else
        # Load root tree when dealing with an error
        ascend_tree(path: RepositoryPath.new)
      end
    end

    # Determines the path to use for the file tree layout. When the file_tree_layout
    # action is called directly (e.g., during SSR), current_path may be empty because
    # the URL has no path component. In that case, if params[:name] contains ref+path
    # info (e.g., "main/dir/file.md"), extract the path from it so the tree can be
    # expanded to show the active file. Falls back to current_path otherwise.
    def path_for_file_tree
      return current_path unless current_path.empty? && params[:name].present?

      _, extracted_path, _ = ref_sha_path_extractor.call(params[:name])
      extracted_path.present? ? RepositoryPath.new(extracted_path) : current_path
    end

    def should_subdirectory?
      !current_path.blank? || params[:files] == "1" || params[:search] == "1" || (params[:name] =~ /\// && params[:name] != params[:branch])
    end

    # When the request is XHR, the current controller/action represent the API endpoint,
    # not the page the user is on. Use the referrer to determine the original page context.
    def referrer_page_route_context
      return {} unless request.xhr? && request.referrer.present?

      referrer_path = URI.parse(request.referrer).path
      route = Rails.application.routes.recognize_path(referrer_path, method: :get) # rubocop:disable Rails/RecognizePath -- We want to use recognize_path to get the controller and action from the referrer URL.
      { controller: route[:controller], action: route[:action] }
    rescue URI::InvalidURIError, ActionController::RoutingError
      {}
    end

    def all_shortcuts_enabled?
      current_user&.settings&.get(:keyboard_shortcuts_preference) == "all"
    end

    def tree_expanded?
      logged_in? ? current_user.settings.get(:tree_view_expanded) : true
    end

    def symbols_expanded?
      logged_in? ? current_user.settings.get(:symbols_view_expanded) : false
    end

    def empty_repo?
      current_repository.heads.empty?
    end
  end
end
