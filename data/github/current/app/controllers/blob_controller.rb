# typed: false
# frozen_string_literal: true

require "github/autonomous_system_actor"

class BlobController < GitContentController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::TokenScanningService,
    ApplicationRecord::Notify,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Notify,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    only: [:blame]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:raw]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Notify,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [:show, :deferred_metadata]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:deferred_ast]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::TokenScanningService,
    ApplicationRecord::Notify,
    only: [:delete]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:preview]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    only: [:detect_language]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IssuesPullRequests,
    only: [:excerpt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    only: [:expand]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Permissions,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    only: [:redirect_to_default_branch]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:contributors]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:contributors_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:sidepanel_metadata]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:blame, :create, :edit, :new, :show, :delete, :preview, :contributors, :contributors_list, :redirect_to_default_branch],
    optional: true

  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(show raw contributors contributors_list).freeze
  MAX_BLOB_SIZE = 5_000_000

  param_encoding :show, :name, "ASCII-8BIT"
  param_encoding :raw, :name, "ASCII-8BIT"
  param_encoding :contributors, :name, "ASCII-8BIT"

  include ActionsHelper
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::SanitizeHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper
  include AvatarHelper
  include BranchesHelper
  include CommitHelper
  include DesktopHelper
  include EditorConfigHelper
  include FeatureGateHelper
  include FundingLinksHelper
  include GitHub::RateLimitedRequest
  include LabelsHelper
  include PlanHelper
  include SiteHelper
  include TextHelper
  include TreeHelper
  include WebCommitControllerMethods
  include BlobMarkupHelper
  include RepositoriesHelper
  include Repos::CodeViewHelper
  include Repos::TreePayloadHelper
  include CodeviewCustomErrorDependency
  include ControllerMethods::Codespaces
  include CopilotInfoHelper
  include CopilotAuthHelper

  allow_verified_fetch only: [:create, :save]

  self.react_bundle_name = "react-code-view"

  rate_limit_requests \
    only: :raw,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    max: 5000,
    key: :rate_limit_key_by_ip

  rate_limit_requests \
    only: :show,
    if: :anon_request_is_rate_limited?,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    max: :blob_show_rate_limit_max,
    key: :default_rate_limit_key

  preload_features [:commit_avatar_stack_view_component], only: :blame
  preload_features [
    :code_view_force_login_blob_show,
    :code_view_logged_out_blob_limit_512k,
    :code_view_logged_out_blob_limit_128k,
    :code_view_logged_out_blob_limit_64k,
    :code_view_logged_out_skip_syntax_highlighting,
    :code_view_logged_out_skip_symbols,
    :code_view_logged_out_minimal_file_tree,
    :code_view_skip_editor_config_retrieval,
    :rate_limit_blob_show_asn_enforced,
    :rate_limit_blob_show_asn,
    :anon_blob_show_rate_limit_max_percentage,
  ], only: :show

  skip_before_action :ask_the_gitkeeper, only: [:sidepanel_metadata, :detect_language]

  before_action :clean_params
  before_action :redirect_for_missing_branch, only: [:show]
  before_action :require_blob, only: [:contributors, :contributors_list, :show, :blame, :edit, :delete, :raw, :save, :destroy]
  before_action :require_blob_from_oid, only: [:excerpt, :expand]
  before_action :ensure_previewing_a_valid_path, only: [:preview]
  before_action :login_required, only: [:create, :save, :preview, :destroy, :add_push_protection_bypass]
  before_action :login_required_with_forced_redirect, only: [:show], if: :force_blob_show_login_enabled?
  before_action :login_required_redirect_for_public_repo, only: [:new, :edit, :delete]
  before_action :confirm_forking, only: [:new, :edit, :delete]
  before_action :require_repository_not_migrating, only: [:new, :edit, :delete]
  before_action :content_authorization_required, only: [:new, :edit, :create, :save, :delete, :destroy]
  before_action :require_xhr, only: [:excerpt]
  before_action :reject_fake_logins, only: [:show], if: :reject_fake_logins_enabled?
  before_action :set_x_repository_download_header, only: [:show]
  before_action :set_x_raw_download_header, only: [:show]

  layout :current_layout

  REACT_ACTIONS = Set.new %w(blame edit show)
  javascript_bundle :repositories, :diffs, unless: -> {
    react_repos_view_enabled? && REACT_ACTIONS.include?(action_name)
  }
  javascript_bundle :editor, only: [:delete, :new, :edit, :save, :create, :add_push_protection_bypass]
  javascript_bundle :"code-menu"
  stylesheet_bundle :code

  rescue_from GitRPC::InvalidObject, with: :tree_redirect

  rescue_from_timeout only: [:show, :edit] do
    render_timeout
  end

  rescue_from_timeout_without_replay only: [:blame] do
    render_timeout
  end

  rescue_from GitHub::RefShaPathExtractor::InvalidPath do
    head 400
  end

  FILE_TEMPLATES = {
    code_of_conduct: {
      filename: "CODE_OF_CONDUCT.md",
      contents: lambda { |string| string },
    },
    readme: {
      filename: "README.md",
      contents: lambda { |repo| repo.generate_readme },
    },
    profile_readme: {
      filename: lambda { |repo| repo.expected_profile_readme_path },
      contents: lambda { |repo| repo.generate_profile_readme },
    },
    org_profile_readme: {
      filename: "profile/README.md",
      contents: lambda { |repo| repo.generate_org_profile_readme },
    },
    org_member_profile_readme: {
      filename: "profile/README.md",
      contents: lambda { |repo| repo.generate_org_member_profile_readme },
    },
    contributing: {
      filename: "CONTRIBUTING.md",
      contents: lambda { |string| string },
    },
    license: {
      filename: "LICENSE",
      contents: lambda { |string| string },
    },
    issue_template: {
      filename: "ISSUE_TEMPLATE.md",
      contents: lambda { |string| string },
    },
    pull_request_template: {
      filename: "PULL_REQUEST_TEMPLATE.md",
      contents: lambda { |string| string },
    },
    repository_funding: {
      filename: FundingLinks::FILENAME,
      contents: lambda { |_| FundingLinks.template },
    },
    dev_container_template: {
      filename: ".devcontainer/devcontainer.json",
      contents: lambda { |_| Codespaces::DevContainers::TEMPLATE_UNIVERSAL_EMPTY },
    },
    workflow_template: {
      filename: ".github/workflows/workflow.yml",
      contents: lambda { |(template_id, repo, user)| Actions::WorkflowTemplates.get_yaml_by_id(template_id, repo, user) },
    },
    security: {
      filename: SecurityPolicy::FILENAME,
      contents: lambda { |_| SecurityPolicy::TEMPLATE },
    },
    dependabot_template: {
      filename: ".github/dependabot.yml",
      contents: lambda { |_| Dependabot::TEMPLATE },
    },
    command_template: {
      filename: ".github/commands/new_command.yml",
      contents: lambda { |_| SlashCommands::StarterCommands::STARTER_COMMAND },
    },
    pages_workflow_template: {
      filename: ".github/workflows/pages.yml",
      contents: lambda { |(template_id, repo, user)| PagesWorkflowTemplate.get_yaml_by_id(template_id, repo, user) },
    },
    other: {
      filename: "",
      contents: lambda { |string| string },
    },
  }

  # These endpoints cause unnecesary, and race-condition riddled updates to the
  # user session, preventing it from timing out. Potentially, from 3rd party sites.
  RACY_ACTIONS = %w(raw show)
  VALID_PULL_REQUEST_CONTEXT = "pull_request"
  README_FILENAME_REGEXP = /\Areadme\.md\z/i
  ISSUE_FORM_PATH_REGEX = "^(\.github\/ISSUE_TEMPLATE\/(?!config).+\.(yaml|yml)$)"

  ALLOWED_NEW_UNCHANGED_CONTENTS_PARAMS = %i[
    value
    readme
    profile_readme
    org_profile_readme
    org_member_profile_readme
    code_of_conduct
    license
    workflow_template
    dev_container_template
    pages_workflow_template
    security_policy
  ].freeze

  def show
    # Gather blob#show non-PII headers to help us distinguish between scrapers and real users.
    if FeatureFlag.vexi.enabled?("collect-blob-show-headers", default: false)
      # We need to validate the headers provided before logging them so that we don't
      # blow out our datadog metrics with invalid values.
      valid_sec_fetch_site_values = %w[same-origin none cross-site same-site]
      sec_fetch_site =
        if request.headers["Sec-Fetch-Site"].blank?
          "MISSING"
        elsif valid_sec_fetch_site_values.include?(request.headers["Sec-Fetch-Site"])
          request.headers["Sec-Fetch-Site"]
        else
          "INVALID"
        end
      GitHub.dogstats.increment("blob.show.request.sec_fetch_site", tags: ["value:#{sec_fetch_site}", "logged_in:#{logged_in?}", "json_request:#{json_request?}"])

      github_verified_fetch = request.headers["GitHub-Verified-Fetch"].present? ? "true" : "MISSING"
      GitHub.dogstats.increment("blob.show.request.github_verified_fetch", tags: ["value:#{github_verified_fetch}", "logged_in:#{logged_in?}", "json_request:#{json_request?}"])
    end

    if !logged_in? && as_actor.feature_flag_enabled?(:rate_limit_blob_show_asn, default: false) && FeatureFlag.vexi.enabled?(:rate_limit_blob_show_asn_enforced, default: false)
      GitHub.dogstats.increment(
        "request_rate_limited_by_asn",
        tags: ["controller:#{self.class.name}", "action:#{action_name}"]
      )

      render \
        body: "You have exceeded a secondary rate limit. Please wait a few minutes before you try again.",
        formats: :html,
        status: 429

      return
    end
    # Redirect to the overview if no path is specified. (path is added to the name if the ref is invalid so check for a slash there)
    if !params[:path].blank? || params[:name].include?("/")
      render_codeview_404 and return if @render_codeview_404
    end

    if params[:path].blank?
      redirect_to tree_url(name: params[:name])
      return
    end

    if params[:raw]
      redirect_to safe_raw_blob_url
      return
    end

    view = current_blob_view_model
    add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)

    # Routes format must be set to false to avoid inferring request format from the file extension.
    # At the same time default file format must be set to `:html` to ensure that rails pages work as expected.
    # According to the docs default format cannot be overridden, therefore we need to set it explicitly based on the
    # Accept header.
    request.format = :json if json_request?

    # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
    # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
    @rendering_react_view = true
    render_react_app(
      app_payload_generator: -> { app_payload },
      payload: get_blob_payload(view),
      page_data: {
        selected_link: :repo_source,
        send_vitals: true,
        richweb: {
          title: view.page_title,
          url: blob_view_url(path_string, current_ref, view.repo),
          description: force_escape_with_transcoding_guess(repo_meta_description),
          image: repository_open_graph_image_url(current_repository),
          card: repository_twitter_image_card(current_repository)
        }
      },
      title: view.page_title,
      turbo: {
        id: "repo-content-turbo-frame",
        target: "_top",
        action: "advance",
        class: full_height? ? "d-flex flex-auto" : ""
      },
      disable_ssr: !FeatureFlag.vexi.enabled?(:react_blob_ssr, current_user, default: false),
    )

  end

  def actions_onboarding_tip # rubocop:todo GitHub/UseRestfulActions
    return nil unless params[:enable_tip].present?
    return nil unless current_repository.organization

    task = OnboardingTasks::Organizations::AutoAssignIssue.new(taskable: current_repository.organization, user: current_user)
    return nil unless task
    return nil if task.completed?

    svg_path = File.join("public", image_path(task.icon_path))
    icon_svg = File.file?(svg_path) ? File.read(svg_path) : nil

    {
      mediaUrl: "https://youtu.be/cP0I9w2coGU",
      mediaPreviewSrc: image_path("modules/dashboard/onboarding/auto-assign-issue-guide.png"),
      taskTitle: task&.title,
      taskPath: request.path,
      iconSvg: icon_svg,
      orgName: current_repository.organization.name
    }
  end

  def codeowners_for_file(codeowners, path, current_user, owned_by_current_user) # rubocop:todo GitHub/UseRestfulActions
    owners_for_path = codeowners.owners_for_path(path)
    owners_for_path -= [current_user] if owned_by_current_user
    (owners_for_path
      .map do |owner|
        next "@#{owner}" if owner.is_a?(Team) #rubocop:todo GitHub/DoNotAllowLogin
        "@#{owner.display_login}"
      end
    ).to_sentence
  end

  def redirect_to_default_branch # rubocop:todo GitHub/UseRestfulActions
    if current_repository.default_branch
      redirect_to blob_url(name: current_repository.default_branch, path: params[:path])
    else
      render_404
    end
  end

  def excerpt # rubocop:todo GitHub/UseRestfulActions
    sha = params[:oid]
    path = path_string
    mode = params[:mode]
    pull_request_context = (params[:context] == VALID_PULL_REQUEST_CONTEXT)

    if path.blank? || mode !~ /\A\d{6}\z/
      head :bad_request
      return
    end

    if pull_request_context
      @pull = PullRequest.where(id: params[:pull_request_id].to_i).first
      pull_request_id = @pull&.id
    end

    respond_to do |format|
      format.html do
        # support old parameter format to prevent failures during feature enabling
        original_last_left = params[:last_left].to_i
        original_last_right = params[:last_right].to_i
        original_left = params[:left].to_i
        original_right = params[:right].to_i
        direction = %w[up down].include?(params[:direction]) ? params[:direction] : nil

        dir = direction.nil? ? "unspecified" : direction
        GitHub.dogstats.increment("blob.excerpt", tags: ["direction:#{dir}"])

        view = create_view_model(Blob::DirectionalBlobExcerpt,
          blob: blob_from_oid,
          direction: direction,
          original_last_left: original_last_left,
          original_last_right: original_last_right,
          original_left: original_left,
          original_right: original_right,
          left_hunk_size: params[:left_hunk_size].presence.try(:to_i),
          right_hunk_size: params[:right_hunk_size].presence.try(:to_i),
          in_wiki_context: in_wiki_context,
          current_repository: current_repository,
          pull_request_context: pull_request_id
        )

        GlobalInstrumenter.instrument("blob.excerpt", {
          repository: current_repository,
          actor: current_user,
          path: path,
          blob_oid: sha,
          first_line: view.hunk_start,
          last_line: view.hunk_start + view.lines.count - 1,
          direction: params[:direction] || "full",
        })

        render(partial: "blob/directional_excerpt", locals: { view: view })
      end
    end
  end

  def expand # rubocop:todo GitHub/UseRestfulActions
    sha = params[:oid]
    path = path_string
    mode = params[:mode]
    ranges = params[:ranges]&.filter_map(&:presence)
    pull_request_context = (params[:context] == VALID_PULL_REQUEST_CONTEXT)

    if path.blank? || mode !~ /\A\d{6}\z/ || ranges.blank? || ranges.empty?
      head :bad_request
      return
    end

    if pull_request_context
      @pull = PullRequest.where(id: params[:pull_request_id].to_i).first
      pull_request_id = @pull&.id
    end

    unless expand_full_blob?(blob_from_oid)
      head :bad_request
      return
    end

    # Normally this would automatically be set anytime we respond with HTML,
    # but here we're actually responding with JSON containing HTML strings
    # so we need to set the header manually
    response.headers["X-HTML-Safe"] = html_safe_nonce

    respond_to do |format|
      format.json do
        fragments = ranges.map do |range|
          # support old parameter format to prevent failures during feature enabling
          original_last_left = range[:last_left].to_i
          original_last_right = range[:last_right].to_i
          original_left = range[:left].to_i
          original_right = range[:right].to_i

          view = create_view_model(Blob::DirectionalBlobExcerpt,
            blob: blob_from_oid,
            direction: "full",
            original_last_left: original_last_left,
            original_last_right: original_last_right,
            original_left: original_left,
            original_right: original_right,
            left_hunk_size: range[:left_hunk_size].presence.try(:to_i),
            right_hunk_size: range[:right_hunk_size].presence.try(:to_i),
            in_wiki_context: in_wiki_context,
            current_repository: current_repository,
            pull_request_context: pull_request_id
          )

          {
            position: range[:position],
            content: render_to_string(
              partial: "blob/directional_excerpt",
              locals: { view: view },
              formats: :html
            )
          }
        end

        render json: fragments
      end
    end
  end

  def raw # rubocop:todo GitHub/UseRestfulActions
    origin = request.headers["HTTP_ORIGIN"]

    render_url = CodeRenderingService::OriginUrlResolver.host_url(origin)
    response.headers["Access-Control-Allow-Origin"] = render_url

    if current_blob.git_lfs?
      target = media_domain_url(current_repository, current_blob.git_lfs_oid)
      if params[:download]
        target_uri = URI.parse(target)
        query = Rack::Utils.parse_query(target_uri.query)
        query["download"] = "true"
        target_uri.query = query.to_query
        target = target_uri.to_s
      end
      redirect_to target
      return
    end

    redirect_to build_raw_url(type: :repository)
  end

  # Calculating the list of top contributors is done async. This is the header list of
  # contributors on the show blob page.
  def contributors # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "blob/contributors", locals: {
          view: create_view_model(Blob::ShowView,
            repo: current_repository,
            tree_name: tree_name,
            commit: current_commit,
            blob: current_blob,
            path: path_string,
          )
        }
      end
    end
  end

  # This is the popup that lists _all_ contributors for a blob when you click the count
  # on the main blob screen.
  def contributors_list # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "blob/contributors_list", locals: {
          view: create_view_model(
            Blob::ShowView,
            repo: current_repository,
            tree_name: tree_name,
            commit: current_commit,
            blob: current_blob,
            path: path_string,
          )
        }
      end
    end
  end

  def blame # rubocop:todo GitHub/UseRestfulActions
    render_codeview_404 and return if @render_codeview_404

    render_blame_react_app
  end

  param_encoding :new, :name, "ASCII-8BIT"

  def new
    set_path_variables(infer_filename: false)
    @branch = params[:name]

    template_type, args = template_from_params
    template = FILE_TEMPLATES.fetch(template_type, :other)

    if feature_enabled_globally_or_for_user?(feature_name: :alternate_user_config_repo, subject: current_repository.owner)
      @filename = if params[:filename]
        params[:filename]
      elsif template[:filename]
        template[:filename].respond_to?(:call) ? template[:filename].call(args) : template[:filename]
      end
    else
      @filename = params[:filename] || template[:filename]
    end
    @filename = current_repository.funding_links_path if @filename == FundingLinks::FILENAME

    @contents = params[:value] || template[:contents].call(args)
    @allow_contents_unchanged = ALLOWED_NEW_UNCHANGED_CONTENTS_PARAMS.any? { |param| params[param].present? }

    return render_404 unless set_form_commit(true)

    if template_type == :code_of_conduct
      flash.now[:notice] = "Your code of conduct template is ready. Please review it below and either commit it to the #{current_repository.default_branch} branch or to a new branch."
      params[:target_branch] = current_repository.heads.temp_name(topic: "add-code-of-conduct")
      params[:quick_pull] = @branch
    elsif template_type == :license
      flash.now[:notice] = "Your license is ready. Please review it below and either commit it to the #{current_repository.default_branch} branch or to a new branch."

      params[:target_branch] = current_repository.heads.temp_name(topic: "add-license")
      params[:quick_pull] = @branch
    end

    # Serve json if soft-nav
    request.format = :json if json_request?

    empty_repo = current_repository.heads.empty?

    add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)

    add_csrf_token(blob_create_path(@path, @branch, current_repository), :post)

    file_tree, file_tree_processing_time, folders_to_fetch = !empty_repo ? ascend_tree(current_path) : [{ "": { items: [], count: 0 } }, false, 0]

    commit_oid = @last_commit

    web_commit_info = web_commit_info(@last_commit, blob_create_path(@path, @branch, current_repository), @branch)
    return render_404 if web_commit_info == false

    edit_info = get_edit_payload(nil, @allow_contents_unchanged)

    path_name = path_string.present? ? path_string : "/"
    if path_name.encoding == ::Encoding::UTF_8 && path_name.valid_encoding?
      path_name
    else
      utf8(path_name)
    end

    # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
    # correct layout template for the React app is used. Temporary, until all paths in controller are React based.

    payload = {
      fileTree: file_tree,
      fileTreeProcessingTime: file_tree_processing_time,
      foldersToFetch: folders_to_fetch,
      repo: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: current_user_can_push?
      ),
      refInfo: {
        name: tree_name,
        listCacheKey: ref_list_cache_key,
        canEdit: true,
        refType: helpers.tree_type,
        currentOid: commit_oid
      },
      currentUser: Repos::ReactPayload.current_user_payload(current_user),
      editInfo: edit_info,
      webCommitInfo: web_commit_info,
      path: path_string,
      copilotInfo: copilot_info_payload(CodeView::Edit, current_repository.organization),
    }

    if show_edit_on_default_option_enabled?
      payload[:refInfo][:canEditOnDefaultBranch] = false
      payload[:refInfo][:fileExistsOnDefault] = if tree_name == current_repository.default_branch
        true
      else
        current_repository.includes_file?(path_string, current_repository.default_branch)
      end
    end

    if helpers.copilot_generate_commit_message_enabled_for_user?
      payload[:copilotGenerateCommitMessageAuthInfo] = {
        apiUrl: Copilot::SKUIsolation.for_user(current_user, public_user_enabled: helpers.cached_sku_isolation_enabled?).api.endpoint,
        ssoOrganizations: sso_organizations,
        copilotAccessAllowed: helpers.copilot_generate_commit_message_allowed?(@branch)
      }
    end

    @rendering_react_view = true
    render_react_app(
      title: "New File at #{path_name} · #{current_repository.name_with_display_owner}",
      app_payload_generator: -> { app_payload },
      payload: payload,
      page_data: { selected_link: :repo_source, send_vitals: true },
      turbo: {
        id: "repo-content-turbo-frame",
        target: "_top",
        action: "advance",
        class: full_height? ? "d-flex flex-auto" : ""
      },
      disable_ssr: !FeatureFlag.vexi.enabled?(:react_blob_ssr, current_user, default: false),
    )
  end

  param_encoding :edit, :name, "ASCII-8BIT"

  # ?flow=1 set if someone intends to create a new flow file
  def edit
    render_codeview_404 and return if @render_codeview_404

    set_path_variables
    @branch = params[:name]
    @allow_contents_unchanged = true if params[:allow_unchanged]
    @autofix_not_found = false

    if current_blob.binary? && !react_repos_view_enabled?
      return redirect_to tree_url(name: params[:name], path: params[:path])
    end

    if params[:code_of_conduct] || params[:license]
      template_type, args = template_from_params
      template = FILE_TEMPLATES.fetch(template_type, :other)

      @filename = template[:filename]
      @filename = current_repository.funding_links_path if @filename == FundingLinks::FILENAME


      @contents = template[:contents].call(args)
      @allow_contents_unchanged = !!(params[:code_of_conduct] || params[:license])
      enable_commit_button = false
      if current_blob.data.gsub("\n", "") != @contents.gsub("\n", "") # remove all \n characters to compare license/code_of_conduct file contents
        enable_commit_button = true
        current_blob.data = @contents
      end
    end

    issue_templates = IssueTemplates.new(current_repository, current_user)
    @issue_template = issue_templates[File.basename(params[:name])]

    if react_repos_view_enabled?
      GitHub.dogstats.increment("repos-react-migration.react", tags: dogstats_request_tags)

      # Serve json if soft-nav
      request.format = :json if json_request?

      add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)
      add_csrf_token(file_save_path(current_repository.owner, current_repository, tree_name, path_string), :post)

      file_tree, file_tree_processing_time, folders_to_fetch = ascend_tree(current_path)

      web_commit_info = web_commit_info(current_repository.refs[@branch]&.target_oid, file_save_path(current_repository.owner, current_repository, tree_name, path_string), @branch)
      return render_404 if web_commit_info == false

      all_shortcuts_enabled = current_user&.settings&.get(:keyboard_shortcuts_preference) == "all"

      return render_404 unless set_form_commit

      # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
      # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
      @rendering_react_view = true

      edit_info = get_edit_payload(current_blob, enable_commit_button)

      if @autofix_not_found
        autofix_type = get_autofix_edit_type
        flash[:error] = "No suggested fix found for #{autofix_type}"
        redirect_to :back and return
      end

      payload = {
        allShortcutsEnabled: all_shortcuts_enabled,
        fileTree: file_tree,
        fileTreeProcessingTime: file_tree_processing_time,
        foldersToFetch: folders_to_fetch,
        repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
        refInfo: {
          name: tree_name,
          listCacheKey: ref_list_cache_key,
          canEdit: true,
          refType: helpers.tree_type,
          currentOid: commit_sha
        },
        currentUser: Repos::ReactPayload.current_user_payload(current_user),
        editInfo: edit_info,
        webCommitInfo: web_commit_info,
        path: path_string,
        copilotInfo: copilot_info_payload(CodeView::Edit, current_repository.organization),
      }

      if helpers.copilot_generate_commit_message_enabled_for_user?
        payload[:copilotGenerateCommitMessageAuthInfo] = {
          apiUrl: Copilot::SKUIsolation.for_user(current_user, public_user_enabled: helpers.cached_sku_isolation_enabled?).api.endpoint,
          ssoOrganizations: sso_organizations,
          copilotAccessAllowed: helpers.copilot_generate_commit_message_allowed?(@branch)
        }
      end

      if show_edit_on_default_option_enabled?
        payload[:refInfo][:canEditOnDefaultBranch] = false
        payload[:refInfo][:fileExistsOnDefault] = if tree_name == current_repository.default_branch
          true
        else
          current_repository.includes_file?(path_string, current_repository.default_branch)
        end
      end

      render_react_app(
        title: "Editing #{current_repository.name}/#{path_string_for_display} at #{h tree_name_for_display} · #{current_repository.name_with_display_owner}",
        app_payload_generator: -> { app_payload },
        payload: payload,
        page_data: { selected_link: :repo_source, send_vitals: true },
        turbo: {
          id: "repo-content-turbo-frame",
          target: "_top",
          action: "advance",
          class: full_height? ? "d-flex flex-auto" : ""
        },
        disable_ssr: !FeatureFlag.vexi.enabled?(:react_blob_ssr, current_user, default: false),
      )
    else
      GitHub.dogstats.increment("repos-react-migration.rails", tags: dogstats_request_tags)

      # to track react.request.duration metric for comparison to react app
      request.env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "rails"

      return render_404 unless establish_target_repository_for_editor_action

      @cancel_url = edit_cancel_url

      if set_form_commit
        instrument(
          "blob.edit.page_view",
          target_repository: @target_repo,
          path: path_string,
        )

        render "blob/edit"
      else
        render_404
      end
    end

  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    @blob_fullwidth = false
    set_path_variables
    @branch = tree_name
    url = destroy_file_path(current_repository.owner, current_repository, @branch, @path, pr: params[:pr])

    if react_repos_view_enabled?
      GitHub.dogstats.increment("repos-react-migration.react", tags: dogstats_request_tags)

      # Serve json if soft-nav
      request.format = :json if json_request?

      add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)
      add_csrf_token(url, :delete)

      file_tree, file_tree_processing_time, folders_to_fetch = ascend_tree(current_path)

      web_commit_info = web_commit_info(current_repository.refs[@branch]&.target_oid, url, @branch)
      return render_404 if web_commit_info == false

      all_shortcuts_enabled = current_user&.settings&.get(:keyboard_shortcuts_preference) == "all"

      return render_404 unless set_form_commit

      synthetic_commit = current_repository.create_commit(@last_commit,
        message: "Temporary Commit for Preview",
        author: current_user,
        files: { "#{current_path}" => "" },
        skip_rule_evaluation: true,
      )

      diffs = synthetic_commit.diff

      diffs_paylod = diffs.map.with_index do |diff, index|
        if GitHub::Markup.can_render?(current_path, current_blob.data)
          context = { path: current_path, committish: tree_name, view: :blob, sanitize_orphan_hrefs: true, use_sourcepos: true }
          before_html = markup_blob_content_if_successful(current_blob, context)

          diff_html = GitHub::HTML::Diff.new(before_html, GitHub::HTMLSafeString::EMPTY, render_url_base: url_for(action: :show)).html
        else
          base_user = current_repository.owner_display_login if diffs.repo != current_repository
          head_user = @forked_repo.owner_display_login if diffs.repo != @forked_repo && @forked_repo.present?

          options = {
            entry: index,
            base_user: base_user,
            head_user: head_user,
            w: diffs.ignore_whitespace?,
            sha1: diffs.parsed_sha1,
            sha2: diffs.parsed_sha2,
            base_sha: diffs.base_sha,
            name: current_repository.default_branch
          }

          load_diff_path = diff_path(current_repository.owner_display_login, current_repository, options)
        end

        {
          deletions: diff.deletions,
          diffHTML: diff_html,
          path: diff.a_path,
          loadDiffPath: load_diff_path,
        }
      end

      # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
      # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
      @rendering_react_view = true
      payload = {
        allShortcutsEnabled: all_shortcuts_enabled,
        fileTree: file_tree,
        fileTreeProcessingTime: file_tree_processing_time,
        foldersToFetch: folders_to_fetch,
        repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
        refInfo: {
          name: tree_name,
          listCacheKey: ref_list_cache_key,
          canEdit: true,
          refType: helpers.tree_type,
          currentOid: commit_sha
        },
        currentUser: Repos::ReactPayload.current_user_payload(current_user),
        deleteInfo: {
          diffs: diffs_paylod,
          isBlob: true,
          truncated: false
        },
        webCommitInfo: web_commit_info,
        path: path_string,
      }

      if show_edit_on_default_option_enabled?
        payload[:refInfo][:canEditOnDefaultBranch] = false
        payload[:refInfo][:fileExistsOnDefault] = if tree_name == current_repository.default_branch
          true
        else
          current_repository.includes_file?(path_string, current_repository.default_branch)
        end
      end

      render_react_app(
        title: "Deleting #{current_repository.name}/#{current_blob.display_name} at #{h tree_name_for_display} · #{current_repository.name_with_display_owner}",
        app_payload_generator: -> { app_payload },
        payload: payload,
        page_data: { selected_link: :repo_source, send_vitals: true },
        turbo: {
          id: "repo-content-turbo-frame",
          target: "_top",
          action: "advance",
          class: full_height? ? "d-flex flex-auto" : ""
        },
        disable_ssr: !FeatureFlag.vexi.enabled?(:react_blob_ssr, current_user, default: false),
      )
    else
      GitHub.dogstats.increment("repos-react-migration.rails", tags: dogstats_request_tags)

      return render_404 unless establish_target_repository_for_editor_action

      if set_form_commit
        render "blob/delete", locals: {
          url: url,
        }
      else
        render_404
      end
    end
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.post?

    url_base = URI.parse(url_for(action: :show)).path
    avoid_diff = params[:avoiddiff] == "true"
    funding_links = FundingLinks.for(blob: preview_contents) if funding_file?

    view = create_view_model(Blob::PreviewView,
      funding_links: funding_links,
      repo: current_repository,
      tree_name: tree_name,
      path: path_string,
      blobname: params[:blobname],
      code: preview_contents,
      old_oid: old_oid_for_preview,
      creates_branch: params[:willcreatebranch],
      render_url_base: url_base,
      responsive: true,
      avoid_diff: avoid_diff
    )

    respond_to do |format|
      format.html do
        GitHub.dogstats.increment("repos-react-migration.rails", tags: dogstats_request_tags)

        render partial: "blob/preview", layout: false, locals: {
          view: view
        }
      end
      format.json do
        GitHub.dogstats.increment("repos-react-migration.react", tags: dogstats_request_tags)

        diff_data = nil
        raw_blob_lines = nil
        styling_directives = nil
        html = nil

        if view.displays_funding? && funding_links
          funding_links_payload = funding_links.funding_payload
          if GitHub.user_abuse_mitigation_enabled?
            funding_links_payload[:reportAbuseLink] = flavored_contact_path(
              report: "#{current_repository.name_with_display_owner} (Repository Funding Links)",
              flavor: "report-abuse",
            )
          end
        elsif view.displays_html?
          html = view.as_html
        elsif view.displays_diff?
          file_list_view = ::Diff::FileListView.new(
            repository: current_repository,
            diffs: view.as_diff,
            params: params,
            expandable: false,
            commentable: false,
            current_user: current_user,
            progressive: view.action == "delete",
            display_diff_ajax_enabled: false,
          )

          file_view = file_list_view.each_diff.to_a[0]

          display_rich_diff = false

          if file_view.code_rendering_service.supports_view? && file_view.code_rendering_service.default_to_rich_diff_view?
            display_url = file_view.code_rendering_service.rich_diff_url(file_view: file_view, file_list_view: file_list_view)
            render_file_type = file_view.code_rendering_service.render_type
            identity_uuid = file_view.code_rendering_service.identity
          elsif (file_view.diff.binary? || file_view.diff.path.end_with?(".svg")) && file_view.supports_rich_diff?
            unless FeatureFlag.vexi.enabled_or_raise?(:skip_old_render_helper_diff, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
              GitHub.dogstats.increment("gh.render.blob_controller_render_case.count")

              display_url = rich_diff_url(
                file_view.diff,
                file_view.diff_blob.render_file_type_for_display(:diff),
                git_repo: (current_repository || file_list_view.repository),
                file_view: file_view,
                file_list_view: file_list_view,
              )
              render_file_type = file_view.diff_blob.render_file_type_for_display(:diff)
              identity_uuid = SecureRandom.uuid
              GitHub.dogstats.increment("gh.render.blob_controller_render_case.success")
            end
          end

          if display_url
            display_data = {
              displayUrl: display_url,
              identityUuid: identity_uuid,
              renderFileType: render_file_type,
              size: file_view.diff_blob.size,
            }
          else
            diff = view.as_diff.to_a[0]

            shd = SyntaxHighlightedDiff.new(current_repository)
            shd.highlight!([diff])
            cache_code, line_syntax = shd.frozen_colorized_lines_with_cache_code(diff)

            diff_data = diff.split_lines.map do |lines|
              left_line = lines[0]
              left_html = left_line.type.present? && left_line.position.present? ? HighlightedDiffLine.for_line(left_line, html_lines: line_syntax).to_html : ""
              right_line = lines[1]
              right_html = right_line.type.present? && right_line.position.present? ? HighlightedDiffLine.for_line(right_line, html_lines: line_syntax).to_html : ""

              { leftLine: { html: left_html, type: left_line.type.upcase, left: left_line.left, right: left_line.right, noNewLine: left_line.nonewline },
                rightLine: { html: right_html, type: right_line.type.upcase, left: right_line.left, right: right_line.right, noNewLine: right_line.nonewline }, cacheCode: cache_code }
            end
          end
        elsif view.displays_blob?
          blob = view.as_blob
          if GitHub::HTML::MarkupFilter.can_render_blob?(blob)
            html, result = format_blob_with_result(blob)
          elsif view.display_with_code_rendering_service?
            rendering_service = view.code_rendering_service
            display_data = {
              displayUrl: rendering_service.url_for_display(commit_oid: current_commit.sha),
              identityUuid: rendering_service.identity,
              renderFileType: rendering_service.render_type,
              size: blob.size,
            }
          else
            styling_directives = blob.styling_directives(strategy: colorize_strategy)
            raw_blob_lines = get_blob_lines(blob)
          end
        end

        json_data = {
          data: {
            diffLines: diff_data,
            rawLines: raw_blob_lines,
            stylingDirectives: styling_directives,
            html: html,
            message: view.as_message,
            messageHtml: view.as_message_supplemental_html,
            displayData: display_data,
            fundingLinks: funding_links_payload,
          },
        }


        render json: json_data
      end
    end
  end

  param_encoding :create, :name, "ASCII-8BIT"

  sig { params(hook_error: T.nilable(String), default_flash_error: String).returns(T::Array[String]) }
  def check_for_rule_violations(hook_error, default_flash_error) # rubocop:todo GitHub/UseRestfulActions
    violations = []
    # Don't show the flash error on hook failures, since we show their output separately
    if hook_error
      @hook_message = default_flash_error
      flash.now[:error] = default_flash_error
      if hook_error.include?("Repository rule violations found")
        hook_error = hook_error.strip.split("\n\n")
        violations = hook_error[1..-1]
        flash.now[:error] = "Please address the rule violations and try again."
      elsif hook_error.include?("The input is too large to process.")
        flash.now[:error] = hook_error
      end
    else
      flash.now[:error] = default_flash_error
    end
    violations
  end

  def create
    return redirect_to(url_for(action: "new")) unless request.post?

    branch, path = extract_branch_path(params[:name])
    @branch = branch

    return render_404 unless establish_target_repository_for_commit_action(branch: branch)

    if @target_repo != current_repository
      params[:quick_pull] ||= [current_repository.owner.display_login, branch].join(":")
    end

    increment_quick_pull_start_stats

    if params[:new_filename].blank? && params[:filename].blank?
      return render(json: { data: { error: "Please specify a name for your file and try again." }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return new
    end

    if params[:new_filename].present?
      @filename = File.basename(params[:new_filename]).strip
      path = params[:new_filename].include?("/") ? File.dirname(params[:new_filename]) : ""
      file_path = [path, @filename].reject(&:blank?).join("/")
    else
      @filename = params[:filename].strip
      path    ||= params[:path].join("/") if params[:path]
      file_path = [path, @filename].reject(&:blank?).join("/")
    end

    file_path = file_path.strip
    @filename ||= File.basename(file_path)

    message = commit_message_from_request("new")

    unless valid_filename?(nil, file_path, branch)
      increment_quick_pull_error_stats
      return render(json: { data: { error: flash.now[:error] }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return new
    end

    params[:commit] = nil if params[:commit].blank?

    if change_conflict?(file_path, params[:commit])
      increment_quick_pull_error_stats
      return render(json: { data: { error: flash.now[:error] }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return new
    end

    contents = params[:value] || "".dup
    contents.gsub!(/\r\n/, "\n")
    contents += "\n" unless contents.ends_with?("\n")

    new_commit_sha, branch, hook_error, full_error = commit_change_to_repo_for_user(@target_repo, current_user, branch, params[:commit], { file_path => contents }, message)

    if check_for_secret_scanning_violation(full_error)
      if react_repos_view_enabled?
        return render json: {
          data: populate_secret_error_data(full_error&.failed_runs&.first&.repository_rule_suite_id)
        }
      else
        return new
      end
    end

    unless branch
      @default_filename = @filename
      violations = check_for_rule_violations(hook_error, "File could not be created")

      increment_quick_pull_error_stats
      return render(json: { data: { error: hook_error.present? ? hook_error : flash.now[:error], error_details: { ruleViolations: violations } }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return new
    end

    if FeatureFlag.vexi.enabled?(:blob_attachment_scanning, default: true) && @filename.ends_with?(".md")
      attach_matching_assets(contents, current_user)
    end

    blob_action_success_with_repo(
      @target_repo, "new", branch, path, new_commit_sha,
      payload: { path: file_path },
      render_as_json: react_repos_view_enabled?,
    )
  end

  param_encoding :save, :name, "ASCII-8BIT"
  param_encoding :save, :new_filename, "ASCII-8BIT"

  def save # rubocop:todo GitHub/UseRestfulActions
    return redirect_to(url_for(action: "edit")) unless request.post?

    branch, path = extract_branch_path(params[:name])
    @branch = branch

    return render_404 unless establish_target_repository_for_commit_action(branch: branch)

    ref = current_repository.heads.find(params[:name])
    return render_404 unless ref

    track_stats = []
    commit = params[:commit]

    if @target_repo != current_repository
      params[:quick_pull] ||= [current_repository.owner.display_login, branch].join(":")
    else
      track_stats.push "maintainer_pushed" if !current_user_can_push?
    end

    increment_quick_pull_start_stats

    message = commit_message_from_request("edit")

    branch          = params[:name]
    new_path_string = params[:new_filename] if params[:new_filename].present?
    new_path_string ||= path_string

    new_path_string = new_path_string.strip
    @filename = File.basename(new_path_string)

    unless valid_filename?(path_string, new_path_string, branch)
      increment_quick_pull_error_stats
      return render(json: { data: { error: flash.now[:error] }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return edit
    end

    if change_conflict?(path_string, commit, ref.target_oid)
      increment_quick_pull_error_stats
      return render(json: { data: { error: flash.now[:error] }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return edit
    end

    check_repository, check_ref = current_repository, ref
    unless check_repository.includes_file?(path_string, check_ref.name)
      base_repository, base_branch = base_repository_and_branch
      base_ref = base_repository.heads.find(base_branch)

      check_repository = base_repository
      check_ref = base_ref
    end

    contents = params[:value]
    contents += "\r\n" unless contents.ends_with?("\n")  # yes, \r\n. The next line will make it \n if applicable
    contents = check_repository.preserve_line_endings(check_ref.target_oid, path_string, contents)

    if path_string != new_path_string
      if current_blob.binary?
        files = { new_path_string => { from: path_string, contents: current_blob.data } }
      else
        files = {
          new_path_string => { from: path_string, contents: contents },
        }
      end
      params[:path] = new_path_string.split("/")
      track_stats.push "edit" if params[:content_changed].present?
      track_stats.push "rename"
    else
      files = { path_string => contents }
    end

    new_commit_sha, branch, hook_error, full_error = commit_change_to_repo_for_user(@target_repo, current_user, branch, commit, files, message)

    if check_for_secret_scanning_violation(full_error)
      if react_repos_view_enabled?
        return render json: {
          data: populate_secret_error_data(full_error&.failed_runs&.first&.repository_rule_suite_id)
        }
      else
        return new
      end
    end

    unless branch
      violations = check_for_rule_violations(hook_error, "File could not be edited")
      increment_quick_pull_error_stats

      @contents = contents
      @allow_contents_unchanged = true

      return render(json: { data: { error: hook_error.present? ? hook_error : flash.now[:error], error_details: { ruleViolations: violations } }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return edit
    end

    if FeatureFlag.vexi.enabled?(:blob_attachment_scanning, default: true) && @filename.ends_with?(".md")
      attach_matching_assets(contents, current_user)
    end

    blob_action_success_with_repo(
      @target_repo, "edit", branch, params[:path], new_commit_sha,
      stats: track_stats,
      payload: { path: params[:path].join("/") },
      render_as_json: react_repos_view_enabled?,
    )
  end

  def destroy
    return redirect_to(url_for(action: "delete")) unless request.delete?

    branch, path = extract_branch_path(params[:name])
    @branch = branch

    return render_404 unless establish_target_repository_for_commit_action(branch: branch)

    ref = @target_repo.heads.find(branch)
    return render_404 unless ref

    if @target_repo != current_repository
      params[:quick_pull] ||= [current_repository.owner.display_login, branch].join(":")
    end

    increment_quick_pull_start_stats

    @filename = params[:filename]
    path      = params[:path].join("/")
    file_path = [path, @filename].reject(&:blank?).join("/")

    message = commit_message_from_request("delete")

    if change_conflict?(file_path, params[:commit], ref.target_oid)
      increment_quick_pull_error_stats
      return render(json: { data: { error: flash.now[:error] }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return delete
    end

    new_commit_sha, branch, hook_error = commit_change_to_repo_for_user(@target_repo, current_user, branch, params[:commit], { file_path => nil }, message)
    unless branch
      violations = check_for_rule_violations(hook_error, "File could not be deleted")

      increment_quick_pull_error_stats
      return render(json: { data: { error: hook_error.present? ? hook_error : flash.now[:error], error_details: { ruleViolations: violations } }, code: 422 }, status: :unprocessable_entity) if react_repos_view_enabled?
      return delete
    end

    blob_action_success_with_repo(
      @target_repo, "delete", branch,
      redirect_back_to_pr? ? params[:path] : File.dirname(path),
      new_commit_sha,
      payload: { path: file_path },
      render_as_json: react_repos_view_enabled?,
    )
  end

  def add_push_protection_bypass # rubocop:todo GitHub/UseRestfulActions
    return redirect_to(url_for(action: "edit")) unless request.post?
    return render_404 unless current_user_can_write_to_repo?
    return render_404 unless SecretScanning::Features::Repo::PushProtection.new(current_repository).enabled? ||
      SecretScanning::Features::User::PushProtection.new(current_user).enabled?

    @allow_contents_unchanged = true
    @contents = params.require(:value)
    reason = params.require(:reason)
    parent_action = params.require(:parent_action)
    bypass_placeholder_ksuid = params.require(:bypass_placeholder_ksuid)

    return head :bad_request unless reason.in?(SecretScanning::Models::BypassReason.string_values)

    success, _ = SecretScanning::Services::PushProtectionService.promote_bypass(reason, current_repository, current_user, bypass_placeholder_ksuid)

    if !success
      flash[:error] = "An error occurred when allowing your secret. Please try again."
    else
      @unblock_secret_success = true
      flash[:secret_detected] = true
    end

    if parent_action == "new"
      return new
    end
    edit
  end

  def blame_not_cached! # rubocop:todo GitHub/UseRestfulActions
    @blame_rendered_from_cache = false
  end

  def detect_language # rubocop:todo GitHub/UseRestfulActions
    # The filename should be encoded as base64, because git paths
    # can contain values unrepresentable in utf-8
    filename = Base64.decode64(params[:filename])

    if params[:full_details]
      language_details = detect_filename_language_with_details(filename)
      render json: {
        language: {
          languageId: language_details&.language_id,
          languageName: language_details&.name
        }
      }
      return
    end

    render json: { language: detect_filename_language(filename) }
  end

  def deferred_ast # rubocop:todo GitHub/UseRestfulActions
    unless current_commit.present?
      render_404
      return
    end

    return render json: { stylingDirectives: nil } if current_blob.nil? # new file

    styling_directives = nil
    styling_directives = current_blob.styling_directives(strategy: colorize_strategy)

    render json: {
      stylingDirectives: styling_directives,
    }
  end

  def deferred_metadata # rubocop:todo GitHub/UseRestfulActions
    unless current_commit.present?
      render_404
      return
    end

    begin
      view = current_blob_view_model
      if current_repository.codeowners?
        ref_name = current_repository.heads.exist?(tree_name) ? tree_name : current_repository.default_branch
        codeowners = Repository::Codeowners.new(current_repository, ref: ref_name, paths: [path_string])
        owned_by_current_user = codeowners.owned_by?(owner: current_user, path: view.path)
        owners_for_file = codeowners_for_file(codeowners, view.path, current_user, owned_by_current_user)
        rule_for_path = codeowners.rule_for_path(view.path)
        rule_for_path_line = rule_for_path&.line
        if owned_by_current_user || owners_for_file.present?
          codeowner_path = blob_path(codeowners.path, codeowners.ref, anchor: "L#{rule_for_path_line}")
        end
      end

      show_license_meta = view.show_license_meta?

      license = nil

      if show_license_meta
        license = {
          name: view.repo.license.name,
          description:  sanitize(view.repo.license.meta["description"], tags: []),
          rules: view.repo.license.rules.to_h.sort_by { |group, _| group }.reverse.to_h
        }
      end
    rescue GitRPC::InvalidObject
      # That's OK, we're in tree view
    end

    if current_repository.has_issues? && !current_repository.archived?
      new_issue_path = new_issue_path(current_repository.owner, current_repository)
    end
    if current_repository.discussions_active? && !current_repository.archived? && current_user&.can_create_discussion?(current_repository)
      new_discussion_path = new_discussion_path(current_repository.owner, current_repository)
    end

    render json: {
      showLicenseMeta: show_license_meta || false,
      license: license,
      newIssuePath: new_issue_path,
      newDiscussionPath: new_discussion_path,
      codeownerInfo: {
        codeownerPath: codeowner_path,
        ownedByCurrentUser: owned_by_current_user,
        ownersForFile: owners_for_file,
        ruleForPathLine: rule_for_path_line
      }
    }
  end

  def sidepanel_metadata # rubocop:todo GitHub/UseRestfulActions
    if current_repository.issue_forms_type_field_enabled?(current_user)
      issue_form_content = IssueForms::SidebarDocs::CONTENT_WITH_TYPE_FIELD
      issue_template_content = IssueForms::SidebarDocs::CONTENT_WITH_TYPES_WITHOUT_PROJECTS_FIELD
    else
      issue_form_content = IssueForms::SidebarDocs::CONTENT
      issue_template_content = IssueForms::SidebarDocs::CONTENT_WITHOUT_PROJECTS_FIELD
    end

    render json:
      {
        docsHtml: {
          workflow: GitHub::Goomba::MarkdownPipeline.to_html(RepositoryActions::Onboarding::SidebarDocs::CONTENT),
          issueForm: GitHub::Goomba::MarkdownPipeline.to_html(issue_form_content),
          issueTemplate: GitHub::Goomba::MarkdownPipeline.to_html(issue_template_content),
          discussionTemplate: GitHub::Goomba::MarkdownPipeline.to_html(DiscussionForms::SidebarDocs::CONTENT),
        },
        marketplaceUrls: {
          workflow: GitHub.enterprise? ? nil : editor_actions_search_url,
          devcontainers: GitHub.enterprise? ? nil : editor_dev_containers_search_url
        }
      }
  end

  def auto_fork_for_editor # rubocop:todo GitHub/UseRestfulActions
    if establish_target_repository(branch: params[:branch], create_fork: true, update_fork: true)
      head :ok
    else
      head :not_found
    end
  end

  private

  UNCACHED_TAGS = ["rendered_from_cache:false"]
  CACHED_TAGS = ["rendered_from_cache:true"]

  def measure_timings
    start_time = GitHub::Dogstats.monotonic_time

    # set up a temporary subscriber to measure graphql execution so it
    # can be subtracted from our overall timing.
    data_loading_time = 0
    callback = -> (_, start, finish, *_) { data_loading_time += (finish - start) }
    ActiveSupport::Notifications.subscribed(callback, "query.graphql") do
      yield
    end

    elapsed_ms = GitHub::Dogstats.duration(start_time)
    data_loading_time_ms = data_loading_time * 1000
    net_elapsed_ms = elapsed_ms - data_loading_time_ms # net == "exclusive of time spent loading data"

    tags = ["ignore_revs_file:#{current_blame.has_ignore_revs_file?}"]

    if @blame_rendered_from_cache
      GitHub.dogstats.increment("blame.cached_render_count", tags: tags)
      tags << CACHED_TAGS
    else
      GitHub.dogstats.increment("blame.uncached_render_count", tags: tags)
      tags << UNCACHED_TAGS
    end

    GitHub.dogstats.distribution("blame.render.dist.net_time_ms", net_elapsed_ms, tags: tags)
    GitHub.dogstats.distribution("blame.render.dist.data_loading_time_ms", data_loading_time_ms, tags: tags)
    GitHub.dogstats.distribution("blame.render.dist.lines", current_blame.lines.size, tags: tags)
    GitHub.dogstats.distribution("blame.render.dist.commits", current_blame.commits.size, tags: tags)
  end

  # Render an error message where blob content would normally live that the
  # operation timed out.
  def render_timeout
    view = create_view_model(Blob::ShowView,
      repo: current_repository,
      tree_name: tree_name,
      commit: current_commit,
      blob: current_blob,
      path: path_string,
      short_path: params[:short_path],
    )
    render "blob/timeout", locals: { view: view }
  end

  helper_method def timeout_if_expired!
    return unless @blame_timer
    if @blame_timer.expired?
      @ignore_revs_failed ||= current_blame.did_blame_with_ignore_revs_timeout?
      if @ignore_revs_failed
        # If we failed to fetch with ignore-revs, reset the timer to try without ignore-revs.
        @blame_timer = GitHub::SafeTimer.new(GitHub.request_timeout(nil) - 2)
        @ignore_revs_failed = false
      else
        raise Timeout::Error, "proactively timing out before middleware kills process"
      end
    end
  end

  helper_method :current_blob, :blob_view_key, :current_blame

  helper_method def current_issue_template # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_issue_template if defined?(@current_issue_template)

    unless current_repository
      return @current_issue_template = nil
    end

    unless editing_issue_template?
      return @current_issue_template = nil
    end

    issue_templates = IssueTemplates.new(current_repository, current_user)
    issue_template_name = File.basename(path_string)
    @current_issue_template = issue_templates[issue_template_name] || IssueTemplate.new(repository: current_repository, filename: File.basename(path_string), user: current_user, type_field_enabled: current_repository.issue_forms_type_field_enabled?(current_user))
  end

  helper_method def editing_issue_template?
    IssueTemplates.valid_path?(path_string)
  end

  # Can the current user commit to the current branch?
  def can_commit_to_branch?
    can_commit_to_branch_status != :blocked
  end

  memoize def can_commit_to_branch_status
    current_repository.can_commit_to_branch_status(current_user, @branch)
  end

  def current_layout
    if @rendering_react_view
      "layouts/repository_with_container"
    else
      "repository"
    end
  end

  # Preserve CRLF or LF line endings in the blob code to prevent the preview
  # diff from marking every line as changed.
  #
  # The form submission always encodes line endings as CRLF, so we detect the
  # blob's original line ending style and convert accordingly.
  #
  # Returns the blob code String to preview.
  def preview_contents
    if previewing_a_new_file?
      params[:code]
    else
      current_repository.preserve_line_endings(old_oid_for_preview, path_string, params[:code])
    end
  rescue GitRPC::InvalidFullOid
    params[:code]
  end

  # Private: determines the old_oid for generating a preview's synthetic commit
  def old_oid_for_preview
    old_oid = params[:commit]
    if old_oid.blank?
      old_oid = current_commit ? current_commit.oid : ""
    end
    old_oid
  end

  # Private: initializes the @path, @filename, and @new_filename_string instance variables
  def set_path_variables(infer_filename: true)
    set_path_variable
    set_filename_variable(infer_filename: infer_filename)
    set_new_filename_string_variable
  end

  # Private: sets @path to params[:path]. If we aren't given a path
  # but we do have a filename, use that.
  def set_path_variable
    @path = params[:path] || [params[:filename]].compact
  end

  # Private: sets @filename to params[:filename].
  # if we aren't given a filename, but we are allowed to infer
  # a filename, extract it from the path. Normally, we don't
  # infer a filename when `#new` is called initially. If #create
  # encounters an error and redisplays #new, we'll have a filename
  #
  # Call *after* set_path_variable, as this depends on @path
  # Cleans up by ensuring it is a stripped, non-null string
  def set_filename_variable(infer_filename: true)
    @filename = params[:filename]
    @filename = @path.try(:last) if infer_filename && @filename.blank?
    @filename ||= ""
    @filename = @filename.strip
  end

  # Private: sets @new_filename_string to params[:new_filename].
  def set_new_filename_string_variable
    @new_filename_string = params[:new_filename]
  end

  # Used in blob/show to render blob contributors inline if they exist in
  # cache. The cache is populated in an async action in this controller.
  def blob_contributors_view_key
    key = [
      "v1.19.#{AvatarHelper::CACHE_VERSION}",
      "contributors",
      current_repository.id,
      current_repository.name_with_owner, # rubocop:disable GitHub/DoNotAllowNameWithOwner name_with_owner as an internal cache key is fine
      current_commit.oid,
      current_blob.id,
      current_blob.mode,
      path_string,
    ]

    git_content_cache_key :blob_contributors, key
  end
  helper_method :blob_contributors_view_key

  # Returns: nil if there is a current commit and a bad path, false if there is no
  #          current commit and/or a blank path, or an instance of Commit
  def current_blob # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_blob if defined?(@current_blob)

    @current_blob =
      if current_commit.nil? || path_string.blank?
        nil
      else
        current_repository.blob(tree_sha, path_string, blob_limits)
      end

    current_blob_from_base if params[:quick_pull] && !@current_blob

    @current_blob
  end

  def current_blob_from_base
    base_repository, base_branch = base_repository_and_branch
    base_oid = base_repository.heads.find(base_branch).target_oid
    @current_blob = base_repository.blob(base_oid, path_string, blob_limits)
  end

  def in_wiki_context
    params[:in_wiki_context] == "true" && current_repository.has_wiki?
  end

  def blob_from_oid # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @blob_from_oid if defined?(@blob_from_oid)

    sha = params[:oid]
    mode = params[:mode]
    diff_repo = if in_wiki_context
      current_repository.unsullied_wiki
    else
      current_repository
    end

    blob_data = begin
      diff_repo.rpc.read_full_blob(sha)
    rescue GitRPC::ObjectMissing
      { "type" => "blob", "oid" => sha, "data" => nil }
    end

    @blob_from_oid = TreeEntry.new(diff_repo, blob_data.merge("path" => path_string, "mode" => mode))
  end

  def require_blob_from_oid
    render_404 unless blob_from_oid.data
  end

  def require_blob
    # Blob always requires a path, so if it's empty, there are 2 possible reasons:
    # 1. Branch is invalid, so we couldn't split ref & path
    # 2. Branch is valid but there's no path, which is not supported in a blob URL, so the URL is bad formed
    # In these 2 cases, we won't render the flash message because:
    # a) We don't have a path to mention in the message
    # b) This is not coming from the user picking a branch where the file is not present (which is the goal of the flash)
    # c) we don't show the error with a banner when CodeView will do it
    skip_ff_check = action_name == "show" || action_name == "blame"

    should_warn = !current_blob && path_string.present? && !(react_repos_view_enabled? || skip_ff_check)
    flash.now[:warn] = "The '#{current_repository.name_with_display_owner}' repository doesn't contain the '#{path_string_for_display}' path in '#{tree_name_for_display}'." if should_warn

    if params[:path].blank? || !current_blob
      if custom_codeview_404?(skip_ff_check) && custom_error_actions?
        @render_codeview_404 = true
      else
        render_404
      end
    end
  end

  def get_blob_lines(blob)
    raw_blob = blob.data.size > MAX_BLOB_SIZE ? nil : blob.data
    raw_blob_lines = raw_blob&.split("\n")
    # Do not include empty lines at the end of a file
    raw_blob_lines.pop if raw_blob_lines&.last&.empty?
    raw_blob_lines
  end

  def ensure_previewing_a_valid_path
    render_404 unless previewing_a_new_file? || previewing_an_existing_file?
  end

  def previewing_a_new_file?
    path_string.nil? || current_repository.includes_directory?(path_string, tree_name)
  end

  def previewing_an_existing_file?
    current_repository.includes_file?(path_string, tree_name)
  end

  def current_blob_issue_template # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @_current_blob_issue_template if defined?(@_current_blob_issue_template)

    if IssueTemplates.valid_path?(path_string)
      if IssueTemplates.valid_yaml_template_path?(current_blob.path, current_repository) && !default_branch?(tree_name)
        config = IssueForms::TemplateConfig.new(input: current_blob.data, path: nil, type_field_enabled: current_repository.issue_forms_type_field_enabled?(current_user)).load
        issue_template = IssueTemplate.new_from_structured_template_config(config: config, repository: current_repository, filename: File.basename(current_blob.path))
      else
        issue_templates = IssueTemplates.new(current_repository, current_user)
        issue_template = issue_templates[File.basename(path_string)]
      end
    end

    @_current_blob_issue_template = issue_template
  end

  def tree_redirect(boom)
    if boom.message =~ /expected blob, got tree/
      redirect_to tree_url(host: GitHub.host_name_with_tenant, path: params[:path], name: params[:name]), status: 301
    else
      render_404
    end
  end

  def establish_target_repository_for_editor_action
    establish_target_repository(branch: @branch, create_fork: request&.post?, update_fork: request.post?)
  end

  def establish_target_repository_for_commit_action(branch:)
    establish_target_repository(branch: branch, create_fork: false, update_fork: request.post?)
  end

  # Internal: Check if filename is acceptable
  #
  # old_path - full path where file used to be
  # new_path - full path where file will be
  # branch   - branch name for this file check
  #
  # Sets flash error
  # Returns Boolean result
  def valid_filename?(old_path, new_path, branch)
    check_existing = old_path != new_path
    validation_message = GitHub::GitFile.validate_path(new_path)
    null_byte = %r{[\x00]}
    slash_or_null_byte = %r{[/\x00]}

    if new_path.include?("\0")
      error = "Your filename contains invalid characters. Please choose a different name and try again."
    else
      filename = File.basename(new_path)
      error = if filename.blank?
        "Please specify a name for your file and try again."
      elsif filename.match(slash_or_null_byte) || new_path.match(null_byte) || %w[. .. .git].include?(filename)
        "Your filename contains invalid characters. Please choose a different name and try again."
      elsif check_existing && current_repository.includes_file?(new_path, branch)
        "A file with the same name already exists. Please choose a different name and try again."
      elsif !current_repository.valid_file_path?(new_path, branch)
        "Sorry, a file exists where you’re trying to create a subdirectory. Choose a new path and try again."
      elsif validation_message
        "That path #{validation_message}. Please choose a different path and try again."
      elsif new_path.length >= 1000
        "Sorry, that file path is too long. Please choose a file path shorter than 1000 characters."
      end
    end

    if error
      flash.now[:error] = error

      @default_filename = filename
      @contents = params[:value]

      false
    else
      flash.delete(:error)

      true
    end
  end

  # Internal: Record and handle success for a blob action
  #
  # Increment stat for blob action
  # Redirect to appropriate followup location or render JSON response (opt-in for react experience as needed)
  #
  # repo            - repository to use for redirection when finished
  # action          - action that was taken (new, edit, delete)
  # branch          - branch name where action was taken
  # path            - path where action was taken
  # new_commit_sha  - sha of the new commit
  # stats           - optional array of stats to increment instead of action
  # payload         - optional additional payload to report in instrumentation
  # render_as_json  - optional flag to render json instead of controller redirection
  #
  # Returns nothing
  def blob_action_success_with_repo(repo, action, branch, path, new_commit_sha, stats: [], payload: {}, render_as_json: false)
    stats << action if stats.empty?
    stats.each { |stat| GitHub.dogstats.increment("blob", tags: ["stat:#{stat}"]) }

    GitHub.instrument "blob.crud", user: current_user

    increment_quick_pull_commit_stats

    instrument(
      "blob.#{action}.succeeded",
      {
        target_repository: repo,
        target_branch: branch,
        action: action,
      }.merge(payload),
    )

    redirect_url = nil
    message = nil
    commit_quorum_poll_path = check_commit_quorum_path(new_commit_sha)

    if params[:quick_pull]
      # redirect to new pull request page
      base = params[:quick_pull]
      base = nil if base == "1"
      range = [base, branch].compact.join("...")
      pull_type = repo.fork? ? "" : "?quick_pull=1"

      redirect_url = compare_path(repo, range) + pull_type
    elsif redirect_back_to_pr?
      redirect_url = "#{redirect_back_to_pr_url}/files##{diff_path_anchor(path.join("/"))}"
    elsif redirect_back_to_owner_profile?
      redirect_url = user_path(repo.owner)
    elsif redirect_back_to_models_repo_page?
      redirect_url = models_prompt_path(repo.owner, repo, branch, payload[:path])
    elsif redirect_back_to_models_compare_page?
      redirect_url = models_prompt_compare_path(repo.owner, repo, branch, payload[:path])
    else
      path = nil if path.blank? || path == "."

      case action
      when "new"
        redirect_path = tree_url(name: branch, path: path)
        redirect_path += "?guidance_task=#{params[:guidance_task]}" if params[:guidance_task].presence
        redirect_url = redirect_path
      when "edit"
        redirect_url = url_for(action: "show", path: path, name: branch)
      when "delete"
        message = "File successfully deleted."
        unless render_as_json
          flash[:notice] = message
        end
        redirect_path = repo.longest_existing_subpath(path, branch)
        redirect_path = nil if redirect_path.empty?
        redirect_url = tree_url(name: branch, path: redirect_path)
      end
    end

    if render_as_json
      render(json: { data: { redirect: redirect_url, message: message, commitQuorumPollPath: commit_quorum_poll_path } }, status: :ok)
    else
      redirect_to redirect_url
    end
  end

  def redirect_back_to_owner_profile?
    params[:redirect_to] == "owner_profile"
  end

  def redirect_back_to_models_repo_page?
    params[:redirect_to] == "models_repo_page"
  end

  def redirect_back_to_models_compare_page?
    params[:redirect_to] == "models_compare_page"
  end

  BLOB_LIMIT_RAW = 10.megabytes
  BLOB_LIMIT_RAILS = 1.megabyte
  BLOB_LIMIT_REACT = 2.megabytes

  def blob_limits
    { truncate: false, limit: blob_size_limit }
  end

  def blob_size_limit
    return BLOB_LIMIT_RAW if params[:action].to_s == "raw"

    if !logged_in?
      # For logged out users, we might want to reduce the blob size limit
      # in certain networks (ASNs) to mitigate the impact of high volume
      # automated traffic.
      if as_actor.feature_flag_enabled?(:code_view_logged_out_blob_limit_64k, default: false)
        GitHub.dogstats.increment("code_view.logged_out_blob_limit", tags: ["limit:64k"])
        return 64.kilobytes
      elsif as_actor.feature_flag_enabled?(:code_view_logged_out_blob_limit_128k, default: false)
        GitHub.dogstats.increment("code_view.logged_out_blob_limit", tags: ["limit:128k"])
        return 128.kilobytes
      elsif as_actor.feature_flag_enabled?(:code_view_logged_out_blob_limit_512k, default: false)
        GitHub.dogstats.increment("code_view.logged_out_blob_limit", tags: ["limit:512k"])
        return 512.kilobytes
      else
        GitHub.dogstats.increment("code_view.logged_out_blob_limit", tags: ["limit:default"])
      end
    end

    return BLOB_LIMIT_REACT if react_repos_view_enabled?
    BLOB_LIMIT_RAILS
  end

  # Internal: extract branch and path from `name` parameter
  #
  # This sort of complicated code is normally handled in RefShaPathExtractor, but it's troublesome
  # when the repo is empty.
  #
  # returns argument when repo has a branch with that name
  #
  # returns [branch, path] when repo has no branches,
  # `branch` being the part of the argument before the first `/` character
  # and `path` being the rest (or the empty string)
  #
  # returns nil otherwise
  def extract_branch_path(name)
    return name if current_repository.heads.exist?(name)

    if current_repository.heads.empty?
      branch, path = name.split("/", 2)
      path ||= ""

      [branch, path]
    end
  end

  def content_authorization_required
    authorize_content(:blob)
  end

  def code_of_conduct
    key = params[:code_of_conduct][:code_of_conduct]
    code_of_conduct = CodeOfConduct.find_by_key(key)
    return "" unless code_of_conduct
    code_of_conduct.generate(params[:code_of_conduct])
  end

  def license
    license = params[:license][:license]
    if license_template = License.find(license)
      hash = {}
      license_template.fields.each do |field|
        field_name = field.key.parameterize separator: "_"

        hash[field_name] = params[:license][field_name.to_sym]
      end

      license_template.generate(field_values: hash)
    else
      ""
    end
  end

  def template_from_params
    case
    when params[:readme]
      [:readme, current_repository]
    when params[:profile_readme] && feature_enabled_globally_or_for_user?(feature_name: :alternate_user_config_repo, subject: current_repository.owner)
      [:profile_readme, current_repository]
    when params[:org_profile_readme]
      [:org_profile_readme, current_repository]
    when params[:org_member_profile_readme]
      [:org_member_profile_readme, current_repository]
    when params[:code_of_conduct]
      [:code_of_conduct, code_of_conduct]
    when params[:contributing]
      [:contributing, params[:value]]
    when params[:license]
      [:license, license]
    when params[:issue_template]
      [:issue_template, params[:value]]
    when params[:pull_request_template]
      [:pull_request_template, params[:value]]
    when params[:repository_funding]
      [:repository_funding, params[:value]]
    when params[:dev_container_template]
      [:dev_container_template, [params[:dev_container_template], current_repository, current_user]]
    when params[:workflow_template]
      if GitHub.actions_enabled?
        [:workflow_template, [params[:workflow_template], current_repository, current_user]]
      else
        [:other, ""]
      end
    when params[:security_policy]
      [:security, ""]
    when params[:pages_workflow_template]
      [:pages_workflow_template, [params[:pages_workflow_template], current_repository, current_user]]
    when params[:dependabot_template]
      [:dependabot_template, ""]
    when params[:command_template] && current_user.slash_commands_enabled?
      [:command_template, ""]
    else
      [:other, ""]
    end
  end

  def route_supports_advisory_workspaces?
    true
  end

  # Private: Instrument a blob event with some payload. By default, the payload
  # will include the actor, repository, branch, and whether the actor can commit
  # to the branch.
  #
  # name    - String name of the event.
  # payload - Hash event payload.
  #
  # Returns nothing.
  def instrument(name, payload = {})
    GlobalInstrumenter.instrument(
      name,
      {
        actor: current_user,
        repository: current_repository,
        branch: params[:name],
        can_commit_to_branch: can_commit_to_branch?,
      }.merge(payload),
    )
  end

  # Disallow session touching for a few racy endpoints
  def allow_session_touching?
    RACY_ACTIONS.exclude?(params[:action])
  end

  def funding_file?
    if path_string.blank? # new file
      params[:blobname]&.downcase == FundingLinks::FILENAME.downcase
    else
      funding_links_path = current_repository&.funding_links_path || FundingLinks::PATH
      path_string.downcase == funding_links_path.downcase
    end
  end

  def expand_full_blob?(tree_entry)
    tree_entry.size < BLOB_LIMIT_RAW && !tree_entry.large?
  end

  # Whether this blob is on the default branch.
  #
  # Returns a Boolean.
  def default_branch?(tree_name)
    tree_name == current_repository.default_branch
  end

  sig { returns(SecretScanning::Features::Repo::PushProtection) }
  memoize def repo_push_protection
    SecretScanning::Features::Repo::PushProtection.new(@target_repo)
  end

  sig { returns(SecretScanning::Features::User::PushProtection) }
  memoize def user_push_protection
    SecretScanning::Features::User::PushProtection.new(current_user)
  end

  def populate_secret_error_data(rule_suite_id)
    has_user_bypass_experience = user_push_protection.has_user_bypass_experience?(@target_repo)

    first_secret = @detected_secrets.first
    secret_location = first_secret.locations.first
    first_secret_location = {} # blob_edit_bypass_metadata expects a hash, this should only end up {} in tests
    if first_secret.locations.first
      first_secret_location = {
        start_line: secret_location.start_line,
        end_line: secret_location.end_line,
        start_line_byte_position: secret_location.start_line_byte_position,
        end_line_byte_position: secret_location.end_line_byte_position
      }
    end

    payload_builder = SecretScanning::Models::React::AllowSecretPayloadBuilder.new(@target_repo, current_user)
    bypass_metadata_payload = payload_builder.blob_edit_bypass_metadata(
      token_metadata_label: first_secret.token_metadata.label,
      bypass_placeholder_ksuid: first_secret.bypass_placeholder_ksuid,
      is_custom_pattern: first_secret.is_custom_pattern?,
      limited_user_bypass_experience_only: has_user_bypass_experience,
      first_secret_location: first_secret_location,
      rule_suite_id: rule_suite_id,
    )

    GitHub.logger.info(
      "updated allow secret payload request from blob editor",
      "code.namespace": self.class.name,
      "code.function": __method__.to_s,
      "gh.repo.id": @target_repo.id,
      "gh.user.id": current_user.id,
      "gh.repo.bypass_placeholder_ksuid": first_secret.bypass_placeholder_ksuid,
      "gh.repo.has_user_bypass_experience": has_user_bypass_experience,
    )

    {
      error: "secret_detected",
      secretBypassMetadata: bypass_metadata_payload,
    }
  end

  def get_blob_payload(view)
    # kick this off first since it's async and can run while we're doing other things
    if should_load_symbols?
      # Retrieve symbols list from blackbird analysis
      symbols = ::BlackbirdSearch::AnalysisClient.query_async(content: current_blob.data, path: path_string_for_display)
    end

    if current_repository.feature_flag_enabled?(:code_view_track_blob_size, default: false)
      GitHub.dogstats.distribution(
        "code_view.blob.size",
        current_blob.data.size,
        tags: ["logged_in:#{logged_in?}", "robot:#{robot?}"]
      )
    end

    @editor_configs = load_blob_editor_configs!(current_commit, current_blob) unless degrade_editor_config_retrieval_enabled?

    payload_tags = ["payload_type: blob"]
    GitHub.dogstats.distribution_time("repos.payload.time", tags: payload_tags) do
      tab_size = tab_size(current_blob.path)
      is_plain = params[:plain].to_s.in?(%w[1 true])

      is_csv = false
      unless blame?
        if csv_or_tsv?(current_blob.extname) && !(current_blob.git_lfs_pointer? || current_blob.data.blank?)
          is_csv = true
          if !is_plain
            csv, csv_error = parse_csv_or_tsv(current_blob)
          end
        end

        render_file_type = current_blob.render_file_type_for_display(:view)
      end

      identity_uuid = SecureRandom.uuid

      if view.display_with_code_rendering_service?
        rendering_service = view.code_rendering_service
        display_url = rendering_service.url_for_display(commit_oid: current_commit.sha)
        identity_uuid = rendering_service.identity
        render_file_type = rendering_service.render_type
      else
        display_url = renderable_blob_url(current_blob, current_repository, raw_blob_url)
      end

      # fetch data for the header
      if current_blob.viewable?
        truncated_loc = current_blob.truncated_loc
        truncated_sloc = current_blob.truncated_sloc
      end

      url_tree = current_branch_or_tag_name || commit_sha
      if view.branch?
        gh_desktop_path = app_clone_url(nil, nil, current_branch_or_tag_name, path_string)
      end

      toc = nil
      richtext = nil
      unless is_plain || blame?
        richtext, result = format_blob_with_result(current_blob, { add_tabindex_to_headings: true })
        toc = result[:toc_headers_hash]
        toc_length = toc&.length || 0
        render_toc = toc_length > 0 && toc_length <= 500
        if render_toc
          Promise.all(toc.map do |toc_item|
            html_label_name_async(toc_item[:text]).then do |html|
              toc_item[:htmlText] = html
            end
          end).sync
        end
      end

      needs_colorize = case
      when blame?
        true
      when richtext
      when current_blob.binary?
      when render_file_type
      when csv
      when current_blob.symlink?
        false
      else
        true
      end

      needs_raw = (needs_colorize || current_blob.symlink? || render_file_type) && view.blob.viewable?

      is_richtext = GitHub::HTML::MarkupFilter.can_render_blob?(current_blob)

      issue_template = current_blob_issue_template
      issue_template_valid = issue_template&.validate
      issue_template_errors = issue_template&.errors&.map { |error| { message: view.rich_form_message(error.full_message), link: error.options[:docs] } }
      issue_template_inputs = issue_template&.inputs&.map do |input|
        input_hash = input.instance_values
        if input.type == "markdown" && input_hash.has_key?("value")
          input_hash["value"] = GitHub::Goomba::MarkdownPipeline.to_html(input.value)
        elsif input_hash.has_key?("description")
          input_hash["description"] = GitHub::Goomba::MarkdownPipeline.to_html(input.description)
        end
        input_hash
      end

      add_csrf_token(create_branch_path, :post)
      add_csrf_token("/repos/preferences", :post)

      if PreferredFile.is_type?(tree_entry: current_blob, type: :codeowners) && !current_repository.plan_supports?(:codeowners)
        show_plan_support_banner = true
        repo_owned_by_current_user = current_repository.owner == current_user
        repo_is_fork = current_repository.fork?
        if repo_owned_by_current_user && !repo_is_fork
          upgrade_path = plan_upgrade_path
          upgrade_data_attributes = feature_gate_upsell_click_attrs(:codeowners, user: current_user)
        end
        if !repo_owned_by_current_user
          show_free_org_gated_feature_message = show_free_org_gated_feature_message?(current_repository, current_user)
          if show_free_org_gated_feature_message
            upgrade_path = upgrade_path(org: current_repository.owner, plan: "business", target: "organization")
            upgrade_data_attributes = feature_gate_upsell_click_attrs(:codeowners, user: current_user)
          end
        end
      end

      if PreferredFile.is_type?(tree_entry: current_blob, type: :codeowners)
        is_codeowners_file = true

        add_csrf_token(codeowners_validity_path, :get)
      end

      if use_minimal_file_tree?
        incomplete_file_tree = true
        file_tree = minimal_file_tree
        folders_to_fetch = []
      else
        incomplete_file_tree = false
        file_tree, file_tree_processing_time, folders_to_fetch = ascend_tree(current_path)
      end

      discussion_template_errors = view.discussion_template&.errors&.map { |error| { message: view.rich_form_message(error.full_message), link: error.options[:docs] } }

      if DiscussionTemplates.valid_path?(path_string)
        discussion_template = current_repository.discussion_templates[path_string]
        discussion_inputs = discussion_template&.config&.body&.map do |input|
          input_hash = input.instance_values
          if input.try(:type) == "markdown" && input_hash.has_key?("value")
            input_hash["value"] = GitHub::Goomba::MarkdownPipeline.to_html(input.value)
          elsif input_hash.has_key?("description")
            input_hash["description"] = GitHub::Goomba::MarkdownPipeline.to_html(input.description)
          end
          input_hash
        end
      end

      all_shortcuts_enabled = current_user&.settings&.get(:keyboard_shortcuts_preference) == "all"

      raw_blob_lines = needs_raw ? get_blob_lines(current_blob) : nil
      tree_expanded = logged_in? ? current_user.settings.get(:tree_view_expanded) : true
      symbols_expanded = logged_in? ? current_user.settings.get(:symbols_view_expanded) : false
      code_line_wrap_enabled = logged_in? ? current_user.settings.get(:code_line_wrap_enabled) : false

      styling_directives = nil
      colorized_lines = nil
      user_agent_string = request.user_agent&.slice(0, Browser.user_agent_size_limit - 1)
      browser_info = Browser.new(user_agent_string)
      should_use_no_virtualization_view = is_correct_browser_and_version_for_inert?(browser_info)
      if needs_colorize || params[:short_path].present?
        if should_use_no_virtualization_view && FeatureFlag.vexi.enabled?(:react_blob_overlay, current_user, default: true) && !raw_blob_lines.nil? && raw_blob_lines.length < 3500 && !code_line_wrap_enabled && !blame?
          colorized_lines = current_blob.colorized_lines(strategy: colorize_strategy)
          GitHub.dogstats.increment("gh.render.blob_controller_render_no_virtualization.count")
        else
          styling_directives = current_blob.styling_directives(strategy: colorize_strategy)
          GitHub.dogstats.increment("gh.render.blob_controller_render_virtualization.count")
        end
      end

      ref_info = {
        name: tree_name,
        listCacheKey: ref_list_cache_key,
        canEdit: view.edit_enabled?,
        refType: helpers.tree_type,
        currentOid: commit_sha
      }

      if show_edit_on_default_option_enabled?
        ref_info[:canEditOnDefaultBranch] = view.edit_enabled_for_default_branch?
        ref_info[:fileExistsOnDefault] = if tree_name == current_repository.default_branch
          true
        else
          current_repository.includes_file?(path_string, current_repository.default_branch)
        end
      end

      return {
        allShortcutsEnabled: all_shortcuts_enabled,
        fileTree: file_tree,
        fileTreeProcessingTime: file_tree_processing_time,
        foldersToFetch: folders_to_fetch,
        incompleteFileTree: incomplete_file_tree,
        repo: Repos::ReactPayload.current_repository_payload(
          current_repository,
          current_user_can_push: current_user_can_push?
        ),
        codeLineWrapEnabled: code_line_wrap_enabled,
        symbolsExpanded: symbols_expanded,
        treeExpanded: tree_expanded,
        refInfo: ref_info,
        path: path_string,
        currentUser: Repos::ReactPayload.current_user_payload(current_user),
        blob: {
          rawLines: raw_blob_lines,
          stylingDirectives: styling_directives,
          colorizedLines: colorized_lines,
          csv: csv,
          csvError: csv_error,
          copilotSWEAgentEnabled: current_repository.copilot_swe_agent_enabled_with_write_permissions?(current_user),
          dependabotInfo: {
            showConfigurationBanner: !!view.show_dependabot_configuration_banner?,
            configFilePath: view.dependabot_config_file_path,
            networkDependabotPath: GitHub.enterprise? ? nil : network_dependabot_path(current_repository.owner, current_repository),
            dismissConfigurationNoticePath: dismiss_notice_path(UserNotice::DEPENDABOT_CONFIGURATION_NOTICE),
            configurationNoticeDismissed: current_user&.dismissed_notice?(UserNotice::DEPENDABOT_CONFIGURATION_NOTICE),
          },
          displayName: current_blob.display_name,
          displayUrl: display_url,
          headerInfo: {
            blobSize: number_to_human_size(current_blob.size),
            deleteTooltip: view.file_action_tooltip(action: :delete),
            editTooltip: view.file_action_tooltip(action: :edit),
            ghDesktopPath: gh_desktop_path,
            isGitLfs: current_blob.git_lfs?,
            onBranch: view.branch?,
            shortPath: blob_short_path(current_blob),
            siteNavLoginPath: site_nav_login_path,
            isCSV: is_csv,
            isRichtext: is_richtext,
            toc: toc&.map { |c| Repos::ReactPayload.camelize_keys(c) }, # rubocop:disable GitHub/AvoidCamelizeKeys
            lineInfo: {
              truncatedLoc: truncated_loc,
              truncatedSloc: truncated_sloc,
            },
            mode: human_mode(current_blob.mode),
          },
          image: current_blob.image?,
          isCodeownersFile: is_codeowners_file,
          isPlain: is_plain,
          isValidLegacyIssueTemplate: view.valid_legacy_template,
          issueTemplate: if issue_template
                           {
                             about: issue_template.about,
                             assignees: issue_template.assignees_string,
                             errors: issue_template_errors,
                             inputs: issue_template_inputs,
                             labels: issue_template.labels_string,
                             projects: issue_template.projects_string,
                             name: issue_template.name,
                             structured: issue_template.structured?,
                             valid: issue_template_valid,
                             type: issue_template.type,
                           }
                         else
                           nil
                         end,
          discussionTemplate: if discussion_template
                                {
                                  errors: discussion_template_errors,
                                  inputs: discussion_inputs,
                                  labels: discussion_template.config.labels.join(", "),
                                  title: discussion_template.config.title,
                                  valid: discussion_template_errors.empty?
                                }
                              else
                                nil
                              end,
          language: current_blob&.language&.name,
          languageID: current_blob&.language&.language_id,
          large: current_blob.large?,
          planSupportInfo: {
            repoIsFork: repo_is_fork,
            repoOwnedByCurrentUser: repo_owned_by_current_user,
            requestFullPath: request.fullpath,
            showFreeOrgGatedFeatureMessage: show_free_org_gated_feature_message,
            showPlanSupportBanner: show_plan_support_banner,
            upgradeDataAttributes: upgrade_data_attributes,
            upgradePath: upgrade_path
          },
          publishBannersInfo: {
            dismissActionNoticePath: dismiss_notice_path(UserNotice::PUBLISH_ACTION_FROM_DOCKERFILE_NOTICE),
            releasePath: new_release_path_helper(query_params: { marketplace: true }),
            showPublishActionBanner: view.show_publish_action_banner?,
          },
          rawBlobUrl: safe_raw_blob_url,
          renderImageOrRaw: render_image_or_raw?(view.blob),
          richText: richtext,
          renderedFileInfo: if render_file_type
                              {
                                identityUUID: identity_uuid,
                                renderFileType: render_file_type,
                                size: current_blob.size,
                              }
                            else
                              nil
                            end,
          shortPath: params[:short_path],
          symbolsEnabled: symbols_enabled?,
          tabSize: tab_size,
          topBannersInfo: {
            overridingGlobalFundingFile: view.overriding_global_funding_file?,
            globalPreferredFundingPath: global_preferred_funding_path(view.repo),
            showInvalidCitationWarning: view.show_invalid_citation_warning?,
            citationHelpUrl: Repositories::Citation.help_url,
            actionsOnboardingTip: actions_onboarding_tip
          },
          truncated: current_blob.truncated?,
          viewable: view.blob.viewable?,
          workflowRedirectUrl: (workflow_yaml_file?) ? filtered_runs_by_file_path(filename: view.filename, lab: view.lab_workflow_file?) : nil,
          symbols: symbols&.sync,
        },
        copilotInfo: copilot_info_payload(
          blame? ? CodeView::Blame : CodeView::Preview,
          current_repository.organization
        ),
        copilotAccessAllowed: with_database_error_fallback(fallback: false) do
          helpers.copilot_chat_enabled_for_current_user? && !helpers.copilot_hidden_by_preference?
        end,
        modelsAccessAllowed: with_database_error_fallback(fallback: false) do
          GitHubModels::User.new(user: current_user).models_access_allowed_for_blob?(blob: current_blob,
            blob_url: safe_raw_blob_url, repository: current_repository)
        end,
        modelsRepoIntegrationEnabled: with_database_error_fallback(fallback: false) do
          GitHubModels::Repository.new(repository: current_repository).models_enabled_for_repo?
        end,
        isMarketplaceEnabled: GitHub.marketplace_enabled?
      }
    end
  end

  def safe_raw_blob_url
    raw_blob_url(name: qualified_tree_name, path: params[:path])
  end

  def is_correct_browser_and_version_for_inert?(browser_info)
    (browser_info.firefox? || browser_info.edge? || browser_info.chrome?) && browser_info.version.to_i >= 124
  end

  def get_edit_payload(current_blob, enable_commit_button)
    add_csrf_token(preview_edit_path, :post)

    license_picker_available = current_user_can_push? && GitHub.license_picker_enabled?
    code_of_conduct_picker_available = current_user_can_push? && GitHub.community_profile_enabled?

    pull_request_url = nil
    content = ""
    if current_blob && !current_blob.binary?
      @editor_configs = load_blob_editor_configs!(current_commit, current_blob)

      code_mirror = {
        indentSize: blob_editor_indent_size(current_blob),
        indentMode: blob_editor_indent_style(current_blob),
        lineWrapping: blob_editor_wrap_mode(current_blob),
        showFileActions: !(current_blob.binary? || current_blob.truncated?)
      }

      variant = params[:variant]

      if variant == "code_scanning" && params[:alert_number].present? && params[:pull_request_number].present?
        pull = PullRequest.with_number_and_repo(params[:pull_request_number].to_i, current_repository)

        if pull.nil?
          @autofix_not_found = true
          return
        end

        pull_request_url = gh_show_pull_request_path(pull)

        alert_number = Integer(params[:alert_number])
        ref_names_bytes = pull.build_ref_names_bytes_for_code_scanning_suggested_fix
        if ref_names_bytes.blank?
          @autofix_not_found = true
          return
        end

        merge_commit_oid = CodeScanningCheckSuite.merge_commit_for(pull_request: pull)

        begin
          suggested_fix = CodeScanning::AutofixSuggestion.fetch_suggested_fix(
            repository: current_repository,
            alert_number: alert_number,
            head_commit_oid: current_commit.oid,
            ref_names_bytes:,
            merge_commit_oid:,
          )
        rescue CodeScanning::AutofixError
          @autofix_not_found = true
          return
        end

        diff_entries = suggested_fix.diff_entries

        begin
          suggested_change = get_suggested_change_from_diff_entries(diff_entries, pull)
          suggested_change.file_contents[path_string] = current_blob
          files = suggested_change.build_new_files
          content = files[path_string]
          enable_commit_button = true
        rescue DiffEntrySuggestedChange::NotFoundError, DiffEntrySuggestedChange::ForbiddenError, DiffEntrySuggestedChange::UnprocessableError
          @autofix_not_found = true
          return
        end

        GlobalInstrumenter.instrument("code_scanning.autofix_event", {
          repository_id: current_repository.id,
          alert_number: alert_number,
          event_type: :AUTOFIX_EVENT_TYPE_EDITED_UI,
          pull_request_id: pull.id,
          pull_request_number: pull.number,
        })
      elsif variant == "dependabot" && params[:dependabot_autofix_job_id].present? && params[:pull_request_number].present?
        pull = PullRequest.with_number_and_repo(params[:pull_request_number].to_i, current_repository)

        if pull.nil?
          @autofix_not_found = true
          return
        end

        autofix_job_id = Integer(params[:dependabot_autofix_job_id])

        response = begin
          Dependabot::Twirp.suggested_fixes_client.get_suggested_fix(
            autofix_job_id: autofix_job_id,
            github_pull_request_number: pull.number,
            github_repo_id: current_repository.id,
          )
        rescue Dependabot::Twirp::BaseError
          @autofix_not_found = true
          return
        end

        suggested_fix = response&.suggested_fix
        if suggested_fix.nil?
          @autofix_not_found = true
          return
        end

        begin
          suggested_change = get_suggested_change_from_suggested_fix(suggested_fix, pull)
          suggested_change.file_contents[path_string] = current_blob
          files = suggested_change.build_new_files
          content = files[path_string]
          enable_commit_button = true
        rescue DiffEntrySuggestedChange::NotFoundError, DiffEntrySuggestedChange::ForbiddenError, DiffEntrySuggestedChange::UnprocessableError
          @autofix_not_found = true
          return
        end

      elsif variant == "code_quality" && params[:code_quality_review_comment_id].present? && CodeQuality.enabled?(current_repository)
        pull = PullRequest.with_number_and_repo(params[:pull_request_number].to_i, current_repository)
        if pull.nil?
          @autofix_not_found = true
          return
        end

        pull_request_url = gh_show_pull_request_path(pull)

        review_comment = PullRequestReviewComment.find(params[:code_quality_review_comment_id].to_i)
        if review_comment.nil?
          @autofix_not_found = true
          return
        end

        # TODO: we should potentially consider the suggested_fix_alert.state here, but perhaps we do want to let
        # users edit e.g. outdated suggestions and let them be responsible for amending the suggestion?
        finding = CodeQualityPullRequestFinding.find(review_comment:)
        suggested_fix = finding&.suggested_fix_alert&.suggested_fix
        if finding.nil? || suggested_fix.nil?
          @autofix_not_found = true
          return
        end

        begin
          suggested_change = get_suggested_change_from_suggested_fix(suggested_fix, pull)
          suggested_change.file_contents[path_string] = current_blob
          files = suggested_change.build_new_files
          content = files[path_string]
          enable_commit_button = true
        rescue DiffEntrySuggestedChange::NotFoundError, DiffEntrySuggestedChange::ForbiddenError, DiffEntrySuggestedChange::UnprocessableError
          @autofix_not_found = true
          return
        end

        GlobalInstrumenter.instrument("code_quality.pr_finding_autofix_event", {
          repository_id: current_repository.id,
          review_comment_id: review_comment.id,
          finding_stable_id: finding.stable_id,
          event_type: :AUTOFIX_EVENT_TYPE_EDITED_UI,
          pull_request_id: pull.id,
          pull_request_number: pull.number,
        })
      else
        content = current_blob.data
      end

    elsif @filename
      code_mirror = {
        showFileActions: true
      }

      if current_blob&.binary?
        content = ""
      else
        content = @contents
      end
    end

    profile_readme_callout_enabled = current_repository.owner == current_user && current_repository.user_configuration_repository?

    upload_extensions = UploadHelper.instance_method(:upload_policy_allowed_extensions).bind(self).call("assets")
    upload_policy_path = upload_policy_path("assets")
    add_csrf_token(upload_policy_path, :post)

    {
      customSlashCommandsDocsUrl: custom_slash_commands_docs_url,
      markdownDocsUrl: GitHub.markdown_docs_url,
      pullRequestUrl: pull_request_url,
      content: content,
      fileName: current_blob.present? ? current_blob.display_name : @filename,
      previewEditPath: preview_edit_path,
      isNewFile: current_blob.nil?,
      binary: current_blob.present? && current_blob.binary?,
      enableCommitButton: enable_commit_button,
      slashCommandsEnabled: current_user.slash_commands_enabled?,
      helpUrl: GitHub.help_url,
      codeMirror: code_mirror,
      editors: {
        stacksEnabled: GitHub.stacks_enabled?,
        actionsEnabled: GitHub.actions_enabled?,
        dependabotEditorEnabled: FeatureFlag.vexi.enabled?(:dependabot_editor_improvements, current_user, default: false),
        devcontainerEditorEnabled: true,
        isEnterprise: GitHub.enterprise?,
        isProxima: GitHub.multi_tenant_enterprise?,
        repositoryActionsEnabled: current_repository.actions_enabled?,
        repositoryActionsReadinessPath: repository_actions_settings_check_readiness_path(current_repository.owner, current_repository),
      },
      templates: {
        issueFormsEnabled: true,
        showIssueFormWarning: false,
      },
      pickers: {
        licensePickerAvailable: license_picker_available,
        licenseToolPath: license_tool_path(branch: @branch),
        codeOfConductPickerAvailable: code_of_conduct_picker_available,
        codeOfConductToolPath: code_of_conduct_tool_path,
      },
      banners: {
        citationHelpUrl: Repositories::Citation.help_url,
        editRepoPath: edit_repository_path(current_repository),
        hasMixedLineEndings: current_blob.present? && current_blob.has_mixed_line_endings?,
        orgMemberProfileReadmeCalloutEnabled: current_repository.is_org_member_profile_repository?,
        orgProfileReadmeCalloutEnabled: current_repository.is_org_profile_repository?,
        profileReadmeCalloutEnabled: profile_readme_callout_enabled,
        replacedDetectedEncoding: current_blob.present? && current_blob.transcoding_necessary? ? current_blob.detected_encoding : nil,
        repositoryCitationTemplateUrl: repository_citation_template_url,
        repositoryFundingLinksEnabled: current_repository.repository_funding_links_enabled?,
        sponsorsEnabled: GitHub.sponsors_enabled?,
      },
      uploadPolicyPath: upload_policy_path,
      uploadExtensions: upload_extensions,
      renderableExtensions: GitHub::Markup.markup_impls.map { |impl| impl.languages.map(&:extensions) }.flatten.uniq,
      isOnboardingGuidance: onboarding_guidance?,
    }
  end

  def blame?
    params[:action] == "blame"
  end

  def current_blob_view_model
    TreeEntry.load_attributes!([current_blob].compact, current_commit.oid)

    if DiscussionTemplates.valid_path?(path_string)
      discussion_template = current_repository.discussion_templates[path_string]
    end

    if workflow_yaml_file? || dev_container_file? || issue_form_template_file? || custom_slash_command? || discussion_template_file?
      @blob_fullwidth = false
    end

    view = create_view_model(
      Blob::ShowView,
      repo: current_repository,
      tree_name: tree_name,
      commit: current_commit,
      blob: current_blob,
      path: path_string,
      path_for_display: path_string_for_display,
      short_path: params[:short_path],
      issue_template: current_blob_issue_template,
      discussion_template: discussion_template,
      valid_legacy_template: IssueTemplates.valid_legacy_template_path?(path_string),
      is_workflow_file: workflow_yaml_file?,
      is_dev_container_file: dev_container_file?,
      parsed_useragent: parsed_useragent
    )

    view
  end

  def render_blame_react_app
    add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)
    blob_view = current_blob_view_model
    blob_payload = get_blob_payload(blob_view)
    blob_payload[:blame] = blame_data
    blame_payload = blob_payload

    # Routes format must be set to false to avoid inferring request format from the file extension.
    # At the same time default file format must be set to `:html` to ensure that rails pages work as expected.
    # According to the docs default format cannot be overridden, therefore we need to set it explicitly based on the
    # Accept header.
    request.format = :json if json_request?

    # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
    # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
    @rendering_react_view = true
    render_react_app(
      app_payload_generator: -> { app_payload },
      payload: blame_payload,
      page_data: { selected_link: :repo_source, send_vitals: true },
      title: "Blaming #{current_repository.name}/#{path_string_for_display} at #{h tree_name_for_display} · #{current_repository.name_with_display_owner}",
      turbo: {
        id: "repo-content-turbo-frame",
        target: "_top",
        action: "advance",
        class: full_height? ? "d-flex flex-auto" : ""
      },
      disable_ssr: !FeatureFlag.vexi.enabled?(:react_blob_ssr, current_user, default: false),
    )
  end

  def app_payload
    Repos::ReactPayload.app_payload(find_file_worker_path, find_in_file_worker_path, github_dev_enabled?)
  end

  def blame_data
    blame_limit = request_time_left - 2
    timeout(blame_limit.positive? ? blame_limit : 0.1) do
      blame_obj = current_blame(line_numbers: get_line_numbers, incremental: false)
      return nil unless blame_obj

      Commit.prefill_users(blame_obj.commits.values)

      client_blame(blame_obj)
    end
  rescue GitRPC::SymlinkDisallowed,
    GitRPC::InvalidIgnoreRevs,
    GitRPC::IgnoreRevsTooBig,
    GitRPC::Timeout,
    Timeout::Error,
    GitRPC::SpawnFailure => err
    {
      errorType:
        case err
        when GitRPC::SymlinkDisallowed
          "symlink_disallowed"
        when GitRPC::InvalidIgnoreRevs
          "invalid_ignore_revs"
        when GitRPC::IgnoreRevsTooBig
          "ignore_revs_too_big"
        when GitRPC::Timeout
        when Timeout::Error
          "blame_timeout"
        when GitRPC::SpawnFailure
          "blame_timeout"
        end,
      ignoreRevs: {
        path: Blame::IGNORE_REVS_FILE_PATH,
        present: false,
        timedOut: false
      },
      ranges: {},
      commits: {},
    }
  end

  def current_blame(line_numbers: [], incremental: false)
    @current_blame ||= current_repository.blame(
      current_commit.oid,
      path_string,
      timeout: request_time_left - 2, # Max of ~8 seconds in prod,
      line_numbers: line_numbers,
      incremental: incremental
    )
  end

  def get_line_numbers
    raw_line_numbers = params[:l]
    return [] unless raw_line_numbers.present?

    if raw_line_numbers.include?(",") && raw_line_numbers.include?("-")
      # Don't support anything fancy
      head :bad_request
    end

    return raw_line_numbers.split(",").map(&:to_i) if raw_line_numbers.include?(",")

    range = raw_line_numbers.split("-").map(&:to_i)
    return [range.first] if range.length == 1
    return (range.first..range.last).to_a if range.length == 2 && range.first < range.last

    head :bad_request
  end

  def client_blame(blame_obj)
    result = {
      ranges: {},
      commits: {}
    }

    blame_obj.each do |lineno, old_lineno, commit, _text, reblame_path|
      aggregate_line_into_client_blame(result, lineno, old_lineno, commit, reblame_path)
    end

    result[:ignoreRevs] = {
      path: Blame::IGNORE_REVS_FILE_PATH,
      present: blame_obj.has_ignore_revs_file?,
      timedOut: blame_obj.did_blame_with_ignore_revs_timeout?
    }

    result
  end

  def aggregate_line_into_client_blame(result, lineno, old_lineno, commit, reblame_path)
    result[:ranges].each_value do |range|
      if range[:commitOid] != commit.oid
        # This is a different commit, so it must be part of a different range
        next
      end

      if range[:start] < lineno && range[:end] > lineno
        # This line is already included in the range; no changes needed
        return
      end

      # If this line is adjacent to an existing range, all we need to do is extend the range
      if range[:start] - 1 == lineno
        range[:start] = lineno
        range[:oldStart] = old_lineno
        return
      end

      if range[:end] + 1 == lineno
        range[:end] = lineno
        range[:oldEnd] = old_lineno
        return
      end
    end

    # There were no matching ranges, so we need to create a new one
    result[:ranges][lineno] = {
      start: lineno,
      oldStart: old_lineno,
      end: lineno,
      oldEnd: old_lineno,
      commitOid: commit.oid,
      reblamePath: reblame_path
    }

    result[:commits][commit.oid] ||= {
      oid: commit.oid,
      message: commit.message,
      shortMessageHtmlLink: helpers.link_to(commit.short_message_text, commit_path(commit), class: "Link--secondary color-fg-default", data: { pjax: true }),
      authorAvatarUrl: commit.author&.primary_avatar_url(80),
      committerName: commit.committer_name,
      committerEmail: commit.committer_email,
      committedDate: commit.committed_date,
      firstParentOid: commit.first_parent_oid
    }
  end

  def custom_error_actions?
    %w[show blame edit].include?(params[:action])
  end

  sig { params(error: T.nilable(StandardError)).returns(T::Boolean) }
  def check_for_secret_scanning_violation(error) # rubocop:todo GitHub/UseRestfulActions
    return false unless error.is_a?(Git::Ref::RepositoryRuleViolationError)

    secret_scanning_runs = error.failed_runs.filter { |r| r.rule_type == RuleEngine::Rules::SecretScanningRule::RULE_NAME }
    return false if secret_scanning_runs.empty?

    run = T.must(secret_scanning_runs[0])

    scan_results = run.evaluation_metadata[SecretScanning::Constants::CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY]
    return false if scan_results&.empty?
    scan_result_hash = scan_results.values.first

    result = SecretScanning::Models::SynchronousScanResult.from_hash(scan_result_hash)
    return false if result.secrets.empty?

    @detected_secrets = result.secrets
    flash[:secret_detected] = true
    true
  end

  def attach_matching_assets(data, user)
    if data.bytesize < 5.megabytes
      GitHub.dogstats.increment("attach_matching_assets.runs", tags: [
        "class:#{self.class.name.underscore}",
        "in_background:true"
      ])
      AttachMatchingAssetsJob.perform_later(current_repository, raw_data: data, attaching_user: user, detach_removed_assets: false)
    else
      GitHub.dogstats.increment("attach_matching_assets.skipped_runs", tags: [
        "class:#{self.class.name.underscore}",
        "in_background:true"
      ])
    end
  end

  # April 11 2025: This feature flag should be short lived to address availability incident 2579.
  def anon_request_is_rate_limited?
    !logged_in? && anon_blob_show_rate_limit_max_percentage&.is_a?(Numeric) && anon_blob_show_rate_limit_max_percentage > 0
  end

  memoize def anon_blob_show_rate_limit_max_percentage
    FeatureFlag.vexi.percentage_of_actors_value_or_raise(:anon_blob_show_rate_limit_max) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
  end

  def blob_show_rate_limit_max
    return 600 if logged_in?

    if anon_blob_show_rate_limit_max_percentage&.is_a?(Numeric) && anon_blob_show_rate_limit_max_percentage > 0
      anon_blob_show_rate_limit_max_percentage * 100
    else
      5000
    end
  end

  sig { returns(GitHub::AutonomousSystemActor) }
  memoize def as_actor
    GitHub::AutonomousSystemActor.for(request)
  end

  sig { returns(T::Boolean) }
  def should_load_symbols?
    !current_blob.binary? &&
      current_blob.data.size > 0 &&
      current_blob.data.size < MAX_BLOB_SIZE &&
      (logged_in? || !as_actor.feature_flag_enabled?(:code_view_logged_out_skip_symbols, default: false)) &&
      !robot?
  end

  sig { returns(T.nilable(Symbol)) }
  memoize def colorize_strategy
    if robot?
      :from_cache_or_plain
    elsif !logged_in? && as_actor.feature_flag_enabled?(:code_view_logged_out_skip_syntax_highlighting, default: false)
      :from_cache_or_plain
    elsif large_blob_as_plain?
      :from_cache_or_plain
    else
      nil
    end
  end

  # Returns true if the current blob is large enough to skip syntax highlighting
  # for logged out users, based on the feature flag.
  #
  # This is used to improve performance for large files by avoiding syntax
  # highlighting, which can be resource-intensive.
  #
  # The threshold is set to 500 kilobytes, and the feature flag is checked
  # to determine if this optimization should be applied.
  def large_blob_as_plain?
    return false if logged_in?
    return false if current_blob.data.size < 500.kilobytes
    FeatureFlag.vexi.enabled?("code_view_logged_out_skip_syntax_highlighting_large_files", as_actor, current_user, current_repository, default: false)
  end


  memoize def use_minimal_file_tree?
    !logged_in? && as_actor.feature_flag_enabled?(:code_view_logged_out_minimal_file_tree, default: false)
  end

  # Produces a similar result to `TreePayloadHelper#ascend_tree`, but
  # without calling GitRPC. The returned tree only contains the direct path
  # from the root to the current path.
  def minimal_file_tree
    file_tree = {}

    current_path.descend.reverse_each.with_index do |path, index|
      next if path.to_s == ""

      file_tree[path.parent.to_s] = {
        items: [
          {
            name: path.basename,
            path: path.to_s,
            contentType: index.zero? ? :file : :directory,
          }
        ],
        totalCount: 1,
      }
    end

    file_tree
  end

  def reject_fake_logins_enabled?
    as_actor.feature_flag_enabled?(:enable_fake_login_checks_blob_controller, default: false)
  end

  def force_blob_show_login_enabled?
    as_actor.feature_flag_enabled?(:code_view_force_login_blob_show, default: false)
  end

  def degrade_editor_config_retrieval_enabled?
    !logged_in? && FeatureFlag.vexi.enabled?(:code_view_skip_editor_config_retrieval, default: false)
  end

  def set_x_repository_download_header
    x_repository_download_header(current_repository) if current_repository
  end

  def set_x_raw_download_header
    begin
      raw_url = build_raw_url
    rescue
      return
    end

    x_raw_download_header(raw_url)
  end

  def get_suggested_change_from_suggested_fix(suggested_fix, pull_request)
    diff_entries = suggested_fix.files.each_with_object([]) do |file, out|
      parser = GitHub::Diff::Parser.new(file.diff_content)
      parser.each do |entry|
        if entry.path == path_string
          out << entry
        end
      end
    end

    get_suggested_change_from_diff_entries(diff_entries, pull_request)
  end

  def get_suggested_change_from_diff_entries(diff_entries, pull_request)
    if diff_entries.nil? || diff_entries.empty?
      raise DiffEntrySuggestedChange::NotFoundError
    end

    DiffEntrySuggestedChange.new(repository: pull_request.head_repository, pull_request:, diff_entries:)
  end

  def get_autofix_edit_type
    case params[:variant]
    when "code_scanning"
      "alert"
    when "code_quality"
      "finding"
    when "dependabot"
      "dependabot breaking change"
    else
      "result"
    end
  end

  def show_edit_on_default_option_enabled?
    FeatureFlag.vexi.enabled?(:show_edit_on_default_option, current_user, default: false)
  end

  def edit_cancel_url
    if %w(code_scanning code_quality).include?(params[:variant]) && params[:alert_number].present? && params[:pull_request_number].present?
      pull = with_database_error_fallback do
        PullRequest.with_number_and_repo(params[:pull_request_number].to_i, current_repository)
      end

      if pull.present?
        return gh_show_pull_request_path(pull)
      end
    end

    url_for(action: "show")
  end
end
