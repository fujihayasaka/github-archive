# typed: strict
# frozen_string_literal: true

module CodeScanning::Status
  extend ActionView::Helpers::TagHelper
  extend ActionView::Helpers::OutputSafetyHelper

  include Api::App::TwirpHelpers
  include Api::Internal::Twirp::Actions::Core::V1

  class ToolInfo
    sig { returns(Turboscan::Proto::ToolStatus) }
    attr_reader :tool

    sig { returns(Repository) }
    attr_reader :repo

    sig { params(tool: Turboscan::Proto::ToolStatus, repo: Repository).void }
    def initialize(tool:, repo:)
      @tool = tool
      @repo = repo
    end

    sig { returns(T::Boolean) }
    def has_manual_workflow?
      tool.categories.any? do |category|
        T.must(category.configuration_group).delivery_origin == :DELIVERY_ORIGIN_YML
      end
    end

    sig { params(max_age: ActiveSupport::Duration).returns(T::Boolean) }
    def has_recent_manual_workflow?(max_age:)
      reference_time = Time.zone.now - max_age

      tool.categories.any? do |category|
        category.configuration_group&.delivery_origin == :DELIVERY_ORIGIN_YML &&
          reference_time < T.must(category.updated_at).to_time
      end
    end

    sig { returns(T::Array[String]) }
    def workflow_paths
      # This method only returns the workflow_paths that exists in the default branch of the repository
      # that match the configuration_group.workflow_path of the category
      workflow_paths = []
      tool.categories.each do |category|
        workflow_path = category.configuration_group&.workflow_path
        if repo.includes_file?(workflow_path)
          workflow_paths << workflow_path
        end
      end
      workflow_paths
    end

    sig { returns(T::Array[Workflow]) }
    def active_workflows
      workflows.select do |workflow|
        workflow.state == "active"
      end
    end

    sig { returns(T::Array[Workflow]) }
    def workflows
      CodeScanning::Status.fetch_workflows(repo, workflow_paths).values
    end

    sig { returns(T::Boolean) }
    def has_managed_delivery?
      tool.categories.any? do |category|
        category.configuration_group&.delivery_origin == :DELIVERY_ORIGIN_MANAGED
      end
    end

    sig { returns(T.nilable(Integer)) }
    def latest_workflow_run_id
      latest_analysis&.workflow_run_id
    end

    sig { returns(T.nilable(Symbol)) }
    def latest_analysis_delivery_origin
      delivery_origin = latest_analysis&.configuration_group&.delivery_origin

      delivery_origin if delivery_origin.is_a?(Symbol)
    end

    sig { returns(T.nilable(Time)) }
    def latest_analysis_date
      latest_analysis&.updated_at&.to_time
    end

    private

    sig { returns(T.nilable(Turboscan::Proto::CategoryStatus)) }
    def latest_analysis
      tool.categories.max_by do |category|
        category.updated_at&.to_time
      end
    end
  end

  class Error
    extend ActionView::Helpers::TextHelper
    extend BasicHelper
    extend CodeScanning::ToolStatusHelper

    sig { params(repository: Repository, workflow_run_id: Integer, text: ActiveSupport::SafeBuffer).returns(ActiveSupport::SafeBuffer) }
    def self.link_category(repository, workflow_run_id, text)
      return text if workflow_run_id.zero?
      return text unless (owner = repository.owner).present?
      tag.a(
        text,
        href: UrlHelpers.workflow_run_file_path(
          workflow_run_id: workflow_run_id,
          repository: repository,
          user_id: owner.display_login
        )
      )
    end

    sig { returns(Turboscan::Proto::CategoryStatus) }
    attr_reader :category

    sig { returns(Integer) }
    attr_reader :level

    sig { returns(T.any(String, ActiveSupport::SafeBuffer)) }
    attr_reader :message

    sig { returns(T.nilable(String)) }
    attr_reader :title

    sig { returns(T.nilable(ActiveSupport::SafeBuffer)) }
    attr_reader :action

    sig do
      params(
        # level should be one of the constants above,
        # but we can't enforce that with Sorbet
        level: Integer,
        message: T.any(String, ActiveSupport::SafeBuffer),
        category: ::Turboscan::Proto::CategoryStatus,
        action: T.nilable(ActiveSupport::SafeBuffer),
        title: T.nilable(String),
      ).void
    end
    def initialize(level:, message:, category:, action: nil, title: nil)
      @title = title
      @message = message
      @level = level
      @category = category
      @action = action
    end

    sig { returns(Integer) }
    def analysis_id
      @category.analysis_id
    end

    sig { returns(String) }
    def configuration_slug
      ::CodeScanning::ToolConfiguration.slug(category: @category)
    end

    sig { params(category: Turboscan::Proto::CategoryStatus).returns(CodeScanning::Status::Error) }
    def self.new_nonexisting_workflow(category)
      Error.new(
        title: "Actions workflow file not found",
        level: ATTENTION,
        message: safe_join([
          "The Action workflow file ",
          tag.code(category.configuration_group&.workflow_path),
          " no longer exists.\n",
          "\nTo stop seeing this error and alerts that were detected by this configuration, ",
          " you can delete the configuration from the menu in the upper right of this page.\n",
          "\n[Learn more about code scanning setup](#{DocsUrlConfig.url_for("code-scanning/configuring-default-setup-for-code-scanning")})",
          "\n[Learn more about removing stale configurations](#{DocsUrlConfig.url_for("code-security/removing-stale-configurations")})",
        ]),
        category: category,
      )
    end

    sig { params(current_repository: Repository, category: Turboscan::Proto::CategoryStatus).returns(CodeScanning::Status::Error) }
    def self.new_failed_processing(current_repository, category)
      message_parts = [
        "Code Scanning failed to process the results for this repository.",
      ]
      if category.configuration_group&.delivery_origin != :DELIVERY_ORIGIN_API
        message_parts += [
          " Please check the ",
          link_category(
            current_repository,
            category.workflow_run_id,
            safe_join(["actions workflow logs for ", format_category(category.category)]),
            ),
          " or reach out to support for more information.",
        ]
      end
      Error.new(
        title: "Code Scanning failed",
        level: DANGER,
        message: safe_join(message_parts),
        category: category,
      )
    end

    sig { params(current_repository: Repository, category: Turboscan::Proto::CategoryStatus, latest_workflow_run_id: T.untyped).returns(CodeScanning::Status::Error) }
    def self.new_workflow_run_failed(current_repository, category, latest_workflow_run_id)
      Error.new(
        title: "Workflow runs failing",
        level: DANGER,
        message: "The most recent run for this workflow failed.",
        category: category,
        action: ::CodeScanning::Status.action_for_workflow_run(current_repository, latest_workflow_run_id),
      )
    end

    sig { params(current_repository: Repository, category: Turboscan::Proto::CategoryStatus, tool: T.untyped, last_scanned_at: T.nilable(Time), level: Integer).returns(CodeScanning::Status::Error) }
    def self.new_outdated_results(current_repository, category, tool, last_scanned_at, level)
      message_parts = [
        tool.name, " last scanned this code ", time_ago_in_words_js(last_scanned_at), ".",
      ]
      if category.configuration_group&.delivery_origin != :DELIVERY_ORIGIN_API
        message_parts += [
          " Please check the ",
          link_category(
            current_repository,
            category.workflow_run_id,
            safe_join(["actions workflow logs for ", format_category(category.category)]),
            ),
          " as it may contain configuration issues.",
        ]
      else
        message_parts += [
          " Please check that this tool is still running correctly.",
        ]
      end
      Error.new(
        title: "Code Scanning results may be out of date",
        level: level,
        message: safe_join(message_parts),
        category: category,
        action: ::CodeScanning::Status.action_for_workflow_run(current_repository, category.workflow_run_id),
      )
    end

    sig { params(current_repository: Repository, category: Turboscan::Proto::CategoryStatus).returns(CodeScanning::Status::Error) }
    def self.no_most_recent(current_repository, category)
      Error.new(
        title: "No code scanning results",
        level: CodeScanning::Status::DANGER,
        message: safe_join([
          "Code Scanning has never received a successful scan for this configuration.\n\n",
          "Please fix any issues and upload an analysis."
        ]),
        category: category,
        action: ::CodeScanning::Status.action_for_workflow_run(current_repository, category.workflow_run_id),
        )
    end

    sig { params(current_repository: Repository, category: Turboscan::Proto::CategoryStatus, workflow: CodeScanning::Status::Workflow).returns(CodeScanning::Status::Error) }
    def self.workflow_not_enabled(current_repository, category, workflow)
      message = case workflow.state
      when "disabled_manually" then "The Actions workflow for this configuration has been manually set to inactive."
      when "deleted" then "The Actions workflow for this configuration has been deleted."
      when "disabled_fork" then "The Actions workflow for this configuration is not enabled as this is a fork."
      when "disabled_inactivity" then "The Actions workflow for this configuration is not enabled due to inactivity."
      else "The Actions workflow for this configuration is not enabled."
      end
      Error.new(
        title: "Actions workflow not enabled",
        level: CodeScanning::Status::ATTENTION,
        message: message,
        category: category,
        action: ::CodeScanning::Status.action_for_workflow_run(current_repository, category.workflow_run_id),
        )
    end
  end

  # Looks at a list of errors and returns the maximum level
  sig { params(errors: T::Array[::CodeScanning::Status::Error]).returns(Integer) }
  def self.max_level(errors)
    errors.map(&:level).max || SUCCESS
  end

  class Messages
    include GitHub::Memoizer

    sig { params(data: T::Hash[String, T::Array[::CodeScanning::Status::Error]]).void }
    def initialize(data = {})
      @data = data
    end

    sig { returns(Integer) }
    def overall_status
      _, first_message = highest_sev_messages.first
      first_message&.level || SUCCESS
    end

    sig { returns(T::Boolean) }
    def all_tools_successful?
      highest_sev_messages.empty?
    end

    sig { params(current_repository: Repository).returns(T.nilable(Primer::Beta::Link)) }
    def error_link_component(current_repository)
      return nil if highest_sev_messages.empty?
      tool_name, message = highest_sev_messages.fetch(0)
      classes = "Link--inTextBlock"

      configuration_group = message.category.configuration_group

      if configuration_group.present? && highest_sev_messages.length.between?(1, 2)
        href = UrlHelpers.repository_code_scanning_results_tool_status_configurations_show_path(
          user_id: current_repository.owner_display_login,
          repository: current_repository,
          tool_name: tool_name,
          configuration_group: ::CodeScanning::ToolConfigurationGroup.slug(configuration_group: configuration_group),
          configuration: message.configuration_slug,
        )
        Primer::Beta::Link.new(href:, classes:).with_content("status page")
      else
        href = UrlHelpers.repository_code_scanning_results_tool_status_show_path(
          user_id: current_repository.owner_display_login,
          repository: current_repository,
          tool_name: tool_name
        )
        Primer::Beta::Link.new(href:, classes:).with_content("tool overview page")
      end
    end

    sig { returns(String) }
    def status_summary
      state = if overall_status == DANGER
        "errors"
      elsif overall_status == ATTENTION
        "warnings"
      end
      return "#{reported_tools} reporting #{state}." if state.present?

      "All tools are working as expected"
    end

    sig { params(tool_name: String, categories: ::Turboscan::Proto::CategoryStatus).returns(T::Array[Error]) }
    def fetch(tool_name, *categories)
      items = @data.fetch(tool_name)
      unless categories.empty?
        slugs = categories.map do |category|
          ::CodeScanning::ToolConfiguration.slug(category: category)
        end.to_set
        items = items.select { |message| slugs.include?(message.configuration_slug) }
      end
      items
    end

    private

    sig { returns(T::Array[[String, ::CodeScanning::Status::Error]]) }
    memoize def highest_sev_messages
      highest_severity = ATTENTION

      filtered_tool_messages = @data.filter_map do |tool_name, errors|
        tool_message = errors.max_by(&:level)

        next if tool_message.nil? || tool_message.level < highest_severity

        highest_severity = tool_message.level if highest_severity < tool_message.level

        [tool_name, tool_message]
      end

      filtered_tool_messages.
        select { |_, message| message.level == highest_severity }.
        sort_by { |tool_name, _| tool_name == "CodeQL" ? 0 : 1 }
    end

    sig { returns(String) }
    def reported_tools
      raise "no tools have errors or warnings" if highest_sev_messages.empty?

      tool_one = highest_sev_messages.fetch(0).first
      case highest_sev_messages.size
      when 1
        "#{ tool_one } is"
      when 2
        tool_two = highest_sev_messages.fetch(1).first
        "#{ tool_one } and #{ tool_two } are"
      else
        "Several tools are"
      end
    end
  end

  class Icon < Primer::Beta::Octicon
    sig { params(level: Integer).returns(T::Hash[Symbol, T.any(Symbol, String)]) }
    def self.octicon_kwargs_for(level:)
      case level
      when CodeScanning::Status::DANGER then { icon: "x-circle-fill", color: :danger, test_selector: "status-danger" }
      when CodeScanning::Status::ATTENTION then { icon: "alert-fill", color: :attention, test_selector: "status-attention" }
      when CodeScanning::Status::SUCCESS then { icon: "check-circle-fill", color: :success, test_selector: "status-success" }
      else { icon: "question", color: :muted, test_selector: "status-question" }
      end
    end

    sig { params(level: Integer, kwargs: T.untyped).void }
    def initialize(level:, **kwargs)
      super(**CodeScanning::Status::Icon::octicon_kwargs_for(level: level), **kwargs)
    end
  end

  class Text < Primer::Beta::Text
    sig { params(level: Integer, kwargs: T.untyped).void }
    def initialize(level:, **kwargs)
      attrs = case level
      when CodeScanning::Status::DANGER then { color: :danger }
      when CodeScanning::Status::ATTENTION then { color: :attention }
      when CodeScanning::Status::SUCCESS then { color: :success }
      else { color: :muted }
      end
      super(**attrs, **kwargs)
    end
  end

  DANGER = 2
  ATTENTION = 1
  SUCCESS = 0

  sig { params(tools: T::Enumerable[Turboscan::Proto::ToolStatus]).returns(T::Set[String]) }
  def self.workflow_paths(tools)
    tools.each_with_object(Set.new) do |tool, workflow_paths|
      tool.categories.each do |category|
        workflow_paths << category.configuration_group.workflow_path
      end
    end
  end

  class Workflow < T::Struct
    const :path, String
    const :name, String
    const :latest_workflow_run, T.nilable(Actions::WorkflowRun)
    const :state, T.nilable(String)

    # these fields come from the workflow YAML file and the user can put anything here
    # use T.untyped rather than risking a runtime error; we check the shape of the data when we use it
    const :schedule, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
    const :events, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps
  end

  sig { params(repository: Repository, workflow_paths: T::Enumerable[String]).returns(T::Hash[String, Workflow]) }
  def self.fetch_workflows(repository, workflow_paths)
    workflow_paths.each_with_object({}) do |workflow_path, out|
      parsed_workflow = ::Actions::ParsedWorkflow.parse_from_yaml(repository, workflow_path)
      unless parsed_workflow.nil?
        workflow = repository.workflows.non_required.find_by(path: workflow_path)

        latest_workflow_run = if workflow.present?
          query = Search::ParsedQuery.stringify(branch: repository.default_branch, is: "success OR failure OR timed_out")
          workflow_runs = Actions::WorkflowRun.search(query:, repo: repository, workflow_id: workflow.id, head_repo_id: repository.id)
          workflow_runs[:workflow_runs]&.first
        end

        out[workflow_path] = Workflow.new(
          path: workflow_path,
          name: parsed_workflow.name,
          schedule: parsed_workflow.schedule,
          events: parsed_workflow.except_schedule,
          latest_workflow_run: latest_workflow_run,
          state: workflow&.state,
        )
      end
    end
  end

  sig { params(last_modified_at: T.nilable(Time), last_scanned_at: T.nilable(Time)).returns(T::Boolean) }
  def self.category_outdated?(last_modified_at:, last_scanned_at:)
    return false if last_modified_at.nil? || last_scanned_at.nil?
    last_modified_at > last_scanned_at + 90.days
  end

  sig { params(repository: Repository, file_path: String, start_line: Integer, end_line: Integer).returns(ActiveSupport::SafeBuffer) }
  def self.action_for_file(repository, file_path, start_line:, end_line:)
    lines = [start_line, end_line].reject(&:zero?).map { |n| "L#{n}" }.join("-")

    args = {
      name: "#{repository.default_branch}/#{file_path}",
      repository: repository.name,
      user_id: repository.owner&.display_login,
    }

    args[:anchor] = lines if lines.present?

    tag.a("View file", href: UrlHelpers.blob_path(**args))
  end

  sig { params(repository: Repository, workflow_path: String).returns(T.nilable(ActiveSupport::SafeBuffer)) }
  def self.action_for_workflow_runs(repository, workflow_path)
    tag.a("View workflow runs", href: UrlHelpers.workflow_runs_list_path(
      workflow_file_name: workflow_path,
      repository: repository,
      user_id: repository.owner&.display_login,
      query: Search::ParsedQuery.stringify(branch: repository.default_branch),
    )) if workflow_path.present?
  end

  sig { params(repository: Repository, workflow_run_id: T.nilable(Integer)).returns(T.nilable(ActiveSupport::SafeBuffer)) }
  def self.action_for_workflow_run(repository, workflow_run_id)
    tag.a("View workflow run", href: UrlHelpers.workflow_run_path(
      workflow_run_id: workflow_run_id,
      repository: repository,
      user_id: repository.owner&.display_login,
    )) if workflow_run_id&.nonzero?
  end

  sig { params(current_repository: Repository, tools: T::Enumerable[Turboscan::Proto::ToolStatus], workflows: T::Hash[String, Workflow]).returns(Messages) }
  def self.messages(current_repository, tools, workflows)
    last_modified_at = current_repository.default_branch_ref&.last_modified_at

    messages = tools.each_with_object({}) do |tool, out|
      errors = []

      found, not_found = tool.categories.partition do |category|
        configuration_group = category.configuration_group

        next unless configuration_group.present?

        configuration_group.delivery_origin != :DELIVERY_ORIGIN_YML || configuration_group.workflow_path.empty? || workflows.include?(configuration_group.workflow_path)
      end

      not_found.each do |category|
        errors << Error.new_nonexisting_workflow(category)
      end

      found.each do |category|
        configuration_group = category.configuration_group

        next unless configuration_group.present?

        workflow = workflows[configuration_group.workflow_path]

        if workflow.present? && workflow.state != "active"
          errors << Error.workflow_not_enabled(current_repository, category, workflow)
        end
      end

      failed = found.select { |category| category.analysis_status == :FAILED && category.messages.empty? }
      if failed.present?
        failed.each do |category|
          errors << Error.new_failed_processing(current_repository, category)
        end
      end

      found.each do |category|
        last_scanned_at = category.updated_at&.to_time

        if category.has_most_recent
          if category_outdated?(last_modified_at: last_modified_at, last_scanned_at: last_scanned_at)
            any_categories_recently_scanned = tool.categories.any? do |other_category|
              !category_outdated?(last_modified_at: last_modified_at, last_scanned_at: other_category.updated_at&.to_time)
            end
            errors << Error.new_outdated_results(current_repository, category, tool, last_scanned_at, any_categories_recently_scanned ? ATTENTION : DANGER)
          end
        else
          errors << Error.no_most_recent(current_repository, category)
        end

        category.messages.each do |message|
          # if the message points to a file in the repository, that's our priority
          action = if message.locations.one? && message.locations.first.file_path&.present?
            location = message.locations.first
            action_for_file(current_repository, location.file_path, start_line: location.start_line, end_line: location.end_line)
          elsif (configuration_group = category.configuration_group).present?
            # if the upload used Actions, try to link somewhere useful
            if configuration_group.delivery_origin == :DELIVERY_ORIGIN_YML && workflows.include?(configuration_group.workflow_path)
              # the message was for a specific workflow run so we can link to that
              if message.has_analysis
                action_for_workflow_run(current_repository, category.workflow_run_id)
              else
                latest_run = workflows[configuration_group.workflow_path]&.latest_workflow_run
                # otherwise link to the latest run for this workflow
                if latest_run.present?
                  action_for_workflow_run(current_repository, latest_run.id)
                else
                  # the final fallback is showing the index page for this workflow, filtered to the current ref
                  action_for_workflow_runs(current_repository, configuration_group.workflow_path)
                end
              end
            end
          end

          errors << Error.new(
            title: message.title,
            level: { DANGER: DANGER, ATTENTION: ATTENTION, SUCCESS: SUCCESS }[message.level],
            message: message.message,
            category: category,
            action: action,
          )
        end

        if (configuration_group = category.configuration_group).present?
          if configuration_group.delivery_origin == :DELIVERY_ORIGIN_YML && workflows.include?(configuration_group.workflow_path)
            latest_workflow_run = workflows[configuration_group.workflow_path]&.latest_workflow_run
            if latest_workflow_run.present? && latest_workflow_run.conclusion != "success"
              errors << Error.new_workflow_run_failed(current_repository, category, latest_workflow_run.id)
            end
          end
        end
      end

      # show highest priority errors first
      out[tool.name] = errors.sort_by(&:level).reverse
    end

    CodeScanning::Status::Messages.new(messages)
  end

  UPLOADING_SARIF_DOCUMENTATION_URL = T.let(DocsUrlConfig.url_for("code-security/uploading-a-sarif-file-to-github"), String)
  UPLOADING_SARIF_FRAGMENT = T.let(tag.a("submit code scanning results externally using the API", href: UPLOADING_SARIF_DOCUMENTATION_URL), ActiveSupport::SafeBuffer)

  sig { params(error: T.nilable(Symbol), repository: Repository, current_user: T.nilable(User)).returns(T.nilable(T.any(String, ActiveSupport::SafeBuffer))) }
  def self.prerequisites_error_to_message(error, repository, current_user)
    actions_path = Rails.application.routes.url_helpers.actions_path(repository.owner, repository)
    actions_settings_path = Rails.application.routes.url_helpers.repository_actions_settings_path(repository.owner, repository)

    case error
    when :repo_archived
      "Code scanning is not available on archived repositories."

    when :advanced_security_disabled
      "Advanced security must be enabled to use code scanning."

    when :code_scanning_not_available
      "Code Scanning is not available"

    when :instance_actions_disabled
      message = [
        "GitHub Actions is not enabled on this instance. To use code scanning please ask your instance administrator to configure Actions, or ",
        UPLOADING_SARIF_FRAGMENT,
        ".",
      ]
      safe_join(message)

    when :instance_actions_disabled_admin
      message = [
        "GitHub Actions is not enabled on this instance. To use code scanning please ",
        tag.a("configure Actions", href: "/setup"),
        ", or ",
        UPLOADING_SARIF_FRAGMENT,
        ".",
      ]
      safe_join(message)

    when :repo_actions_disabled_by_owner
      message = [
        "GitHub Actions is disabled on this repostiory by an enterprise or organization policy. To use code scanning, please ask your organization administrator to enable Actions, or ",
        UPLOADING_SARIF_FRAGMENT,
        ".",
      ]
      safe_join(message)
    when :repo_actions_disabled
      message = [
        "GitHub Actions is disabled on this repository. To use code scanning please ",
        tag.a("enable it", href: actions_settings_path),
        ", or ",
        UPLOADING_SARIF_FRAGMENT,
        ".",
      ]
      safe_join(message)

    when :fork_actions_disabled
      message = [
        "GitHub Actions is disabled on this repository because it is a fork. To use code scanning please ",
        tag.a("enable it", href: actions_path),
        ", or ",
        UPLOADING_SARIF_FRAGMENT,
        ".",
      ]
      safe_join(message)

    when :actions_policy_disabled
      message = [
        "GitHub Actions policy is limiting the use of some required actions. To use code scanning, allow actions from `actions/*` and `github/codeql-action/*` in",
        tag.a(" your policy", href: actions_settings_path),
        ", or ",
        UPLOADING_SARIF_FRAGMENT,
        ".",
      ]
      safe_join(message)
    end
  end

  sig { params(repository: Repository, current_user: T.nilable(User), options: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(Symbol)) }
  def self.validate_prerequisites(repository, current_user, options: {})
    # 1 - Repository must not be archived
    if repository.archived?
      return :repo_archived
    end

    # 2 - Advanced security must be enabled
    if !repository.advanced_security_usable? && !options&.dig(:skip_ghas_check?)
      return :advanced_security_disabled
    end

    # 3 - Code scanning must be available
    if !repository.code_scanning_available?
      return :code_scanning_not_available
    end

    # 4 - Instance Actions must be enabled
    if !GitHub.actions_enabled?
      if current_user&.site_admin? && !GitHub.cluster_regular_enabled?
        return :instance_actions_disabled_admin
      else
        return :instance_actions_disabled
      end
    end

    # 5 - Repository Actions must be enabled
    if repository.actions_disabled?
      if repository.actions_disabled_by_owner?
        return :repo_actions_disabled_by_owner
      else
        return :repo_actions_disabled
      end
    end

    # 5B - Check forks
    if repository.fork? && GitHub.launch_github_app.installations_on(repository.owner).with_repository(repository).none? && repository.workflow_file_present?(repository.default_branch)
      return :fork_actions_disabled
    end

    # 6 - Check policy in dotcom
    actions_not_allowed_to_execute_reason = check_actions_policy_allows_for_execution(repository)
    if actions_not_allowed_to_execute_reason.present?
      return actions_not_allowed_to_execute_reason
    end

    # 7 - Check requirements specific to default setup
    if options&.[](:include_default_setup_prerequisites)
      return validate_default_setup_runners(repository, options: options)
    end

    nil
  end

  sig { params(repository: Repository).returns(T.nilable(Symbol)) }
  def self.check_actions_policy_allows_for_execution(repository)
    unless GitHub.enterprise?
      request = MonolithTwirp::Actions::Core::V1::CheckActionsPolicyRequest.new(
        actions: Turboscan::Workflow::ACTIONS_TO_CHECK,
        repository_id: MonolithTwirp::Actions::Core::V1::Identity.new(global_id: repository.next_global_id)
      )
      response = Api::Internal::Twirp::Actions::Core::V1::CheckActionsPolicy.call(request)

      return :failed_fetching_actions_policy if response.is_a?(Twirp::Error)

      unless response[:is_execution_allowed]
        :actions_policy_disabled
      end
    end
  end

  CODE_SCANNING_RUNNER_LABELS = T.let(%w[code-scanning], T::Array[String])
  CODE_SCANNING_MACOS_RUNNER_LABELS = T.let(%w[macOS code-scanning], T::Array[String])

  sig { params(repository: Repository, options: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(Symbol)) }
  def self.validate_default_setup_runners(repository, options: {})
    only_swift_to_enable = options&.[](:languages)&.include?("swift") && options&.[](:languages).size == 1

    if only_swift_to_enable
      return :no_macos_runners_assigned unless desired_runners?(repository:, desired_labels: [options[:runner_label], "macOS"]) if options.present? && options[:runner_label].present?
    end

    return :no_runners_assigned unless desired_runners?(repository:, desired_labels: [options[:runner_label]]) if options.present? && options[:runner_label].present?

    nil
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.mac_os_runner?(repository:)
    desired_runners?(repository:, desired_labels: CODE_SCANNING_MACOS_RUNNER_LABELS)
  end

  sig { params(repo_id: Integer, ref: String, tool_name: String).returns(Turboscan::Proto::FilesExtractedSummaryResponse) }
  def self.fetch_extracted_files_summary(repo_id, ref, tool_name)
    begin
      response = GitHub::Turboscan.get_files_extracted_summary(
        repository_id: repo_id,
        ref: ref,
        tool: tool_name,
      )
    rescue Faraday::Error => e
      return ::Turboscan::Proto::FilesExtractedSummaryResponse.new
    end

    data = response&.data

    if response.nil? || data.nil? || response.error.present?
      return ::Turboscan::Proto::FilesExtractedSummaryResponse.new
    end

    data
  end

  sig { params(trigger: String, repo_id: Integer, ref: String, tool: Turboscan::Proto::ToolStatus, messages: CodeScanning::Status::Messages).void }
  def self.emit_tool_status_hydro_event(trigger, repo_id, ref, tool, messages)
    summary = fetch_extracted_files_summary(repo_id, ref, tool.name)
    messages_for_tool = messages.fetch(tool.name)
    delivery_origins = tool.categories.map { |c| c.configuration_group.delivery_origin }.uniq

    delivery_origin_status = tool.categories.each_with_object({}) do |category, statuses|
      delivery_origin = category.configuration_group&.delivery_origin
      next unless delivery_origin
      delivery_origin = delivery_origin.to_s # the Hydro schema needs string keys, not enum

      status = max_level(messages.fetch(tool.name, category))
      if statuses.include? delivery_origin # Have we already found a status for this delivery origin?
        # We might have multiple categories for DELIVERY_ORIGIN_YML, so
        # include the status of the worst one. This matches what we do
        # for overall status.
        statuses[delivery_origin] = status if status > statuses[delivery_origin]
      else
        statuses[delivery_origin] = status
      end

      statuses
    end
    GlobalInstrumenter.instrument("code_scanning.tool_status", {
      status_trigger: trigger,
      repository_id: repo_id,
      ref: ref,
      tool_name: tool.name,
      status: max_level(messages_for_tool),
      messages: messages_for_tool,
      total_extracted: summary.total_extracted,
      languages_extracted: summary.languages_extracted,
      delivery_origins: delivery_origins,
      delivery_origin_status: delivery_origin_status
    })
  end

  sig { params(repository: Repository, desired_labels: T::Array[String]).returns(T::Boolean) }
  private_class_method def self.desired_runners?(repository:, desired_labels:)
    # In theory even repositories on DotCom should have the default runner group, but in practice it seems like this group is not always created.
    # Since we know hosted runners should always be available on DotCom, we can just skip this check there.
    return true unless GitHub.enterprise?

    SecurityProductsEnablement::Actions::RunnerChecker.new(repository).
      labelled_runners_available?(desired_labels: desired_labels)
  end
end
