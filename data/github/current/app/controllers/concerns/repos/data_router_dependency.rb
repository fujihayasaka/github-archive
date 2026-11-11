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
    include Repos::DataRouterFlagDependency
    include CopilotInfoHelper

    abstract!

    sig { abstract.returns(T.untyped) }
    def current_user; end

    requires_ancestor { AbstractRepositoryController }

    EMPTY_FILE_TREE = [{ "": { items: [], totalCount: 0 } }, 0, []].freeze

    def layout_route_payload
      GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: layout"]) do
        upload_policy_path = upload_policy_path("assets")

        CodeViewPayloads::LayoutRoutePayload.new({
          repo: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          currentUser: Repos::ReactPayload.current_user_payload(current_user),
          uploadToken: authenticity_token_for(upload_policy_path, method: :post),
          allShortcutsEnabled: all_shortcuts_enabled?,
          treeExpanded: tree_expanded?,
          path: path_string.empty? ? "/" : path_string,
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
        })
      end
    end

    def codeview_sidebar_about_payload(view:)
      GitHub.dogstats.distribution_time("repos.payload.time", tags: ["payload_type: codeview_sidebar_about"]) do
        sidebar = Repos::CodeViewSidebar::CodeViewSidebar.new(view_model: view, current_user: current_user, current_repository: current_repository)
        CodeViewPayloads::OverviewSidebarAboutPayload.new(sidebar.about_payload.serialize)
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

      return ascend_tree(path: current_path, include_current: true) if !error

      # Best-attempt to get the file tree in case of 404s and 500s from the blob.
      file_tree, file_tree_processing_time, folders_to_fetch = if current_path.empty?
        EMPTY_FILE_TREE
      else
        # Load root tree when dealing with an error
        ascend_tree(path: RepositoryPath.new)
      end
    end

    def should_subdirectory?
      # If we request a JSON, it's from the Code View and we want the payload of the root folder,
      # we're not looking for the overview page. We just want to render the root in the Code View.
      return true if request.headers["Accept"] == "application/json" && !data_router_feature_flag_enabled?

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
