# typed: true
# frozen_string_literal: true

require "actions-runner-admin"
require "test_helper"
require "test_helpers/launch/self_hosted_runners_helper"
require "test_helpers/launch/runner_groups_helper"
require "test_helpers/launch/setup_tenant_helper"


class StatusTestCase < GitHub::TestCase
  include Launch::SelfHostedRunnersHelper
  include GitHub::ComponentTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business!
    @user = create(:user)
    @owner = create(:organization)
    @owner.add_member(@user)
    @repository = create(:private_repository, owner: @owner, from_example: :with_tokens)
    @ruby = create(:language, language_name: create(:language_name, name: "Ruby"))
    @swift = create(:language, language_name: create(:language_name, name: "Swift"))
  end

  setup do
    GitHub.stubs(:code_scanning_enabled?).returns(true)
    @default_setup_validation_options = { include_default_setup_prerequisites: true }
    @default_setup_validation_options[:runner_label] = "code-scanning" if GitHub.enterprise?
  end

  context "fetch_workflows" do
    test "returns a mapping of workflows to workflow_run_ids" do
      GitHub.actions_enabled = true
      make_trusted_oauth_apps_owner
      github_app = create(:launch_integration)
      # required for enterprise tests otherwise multiple_check_suites_per_sha_enabled? will not be true
      GitHub.stubs(:launch_github_app).returns(github_app)

      check_suite_name = "CodeQL analysis"

      workflow_file_path_1 = ".github/workflows/codeql-analysis-1.yml"
      workflow_file_path_2 = ".github/workflows/codeql-analysis-2.yml"

      @repository.refs.find(@repository.default_branch).append_commit({ message: "Add a thing", author: @user }, @user) do |changes|
        changes.add(workflow_file_path_1, "add workflow")
      end
      commit = @repository.refs.find(@repository.default_branch).append_commit({ message: "Add a thing", author: @user }, @user) do |changes|
        changes.add(workflow_file_path_2, "add workflow")
      end

      check_suite_1 = create(
        :check_suite_for_actions_app,
        :success,
        head_sha: commit.oid,
        repository: @repository,
        head_repository: @repository,
        event: "push",
        name: check_suite_name,
        workflow_file_path: workflow_file_path_1,
      )

      check_suite_2 = create(
        :check_suite_for_actions_app,
        :success,
        head_sha: commit.oid,
        repository: @repository,
        head_repository: @repository,
        event: "push",
        name: check_suite_name,
        workflow_file_path: workflow_file_path_2,
      )

      workflows = CodeScanning::Status.fetch_workflows(@repository, [workflow_file_path_1, workflow_file_path_2])

      assert workflows.size == 2

      workflow_1 = workflows[check_suite_1.workflow_file_path]
      refute_nil workflow_1
      assert_equal workflow_file_path_1, workflow_1&.path

      workflow_2 = workflows[check_suite_2.workflow_file_path]
      refute_nil workflow_2
      assert_equal workflow_file_path_2, workflow_2&.path
    end
  end

  context "messages" do
    test "returns an error when the analysis has turboscan errors" do
      path = "re-wf/1.yml"
      data = { "name" => "Required CI", true => { "push" => nil, "pull_request" => { "branches" => ["main"] } } }
      parsed_workflow = Actions::ParsedWorkflow.new(repository: @repository, path: path, data: data, file_size: data.size)

      errors = CodeScanning::Status.messages(
        @repository,
        [::Turboscan::Proto::ToolStatus.new(
          name: "CodeQL",
          categories: [
            ::Turboscan::Proto::CategoryStatus.new(
              has_most_recent: true,
              workflow_run_id: 1,
              messages: [{ title: "boom", message: "boom", level: :ATTENTION }],
              configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
            ),
          ],
        )],
        {
          1 => {
            path: ".github/workflow/test.txt",
            yaml: parsed_workflow,
          }
        },
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal messages.size, 1
      assert_equal T.must(messages.first).title, "boom"
    end

    test "returns an error when the workflow is missing" do
      errors = CodeScanning::Status.messages(
        @repository,
        [::Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: [
          ::Turboscan::Proto::CategoryStatus.new(
              has_most_recent: true,
              configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(
                delivery_origin: :DELIVERY_ORIGIN_YML,
                workflow_path: ".github/workflows/codeql-analysis.yml",
              ),
            ),
          ])
        ],
        {},
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal messages.size, 1
      assert_equal T.must(messages.first).title, "Actions workflow file not found"
    end

    test "returns no error for an api upload with no workflow run id" do
      errors = CodeScanning::Status.messages(
        @repository,
        [
          ::Turboscan::Proto::ToolStatus.new(
            name: "CodeQL",
            categories: [
              ::Turboscan::Proto::CategoryStatus.new(has_most_recent: true, workflow_run_id: 0, configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API)),
            ],
          ),
        ],
        {},
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal messages.size, 0
    end

    context "#error_link_component" do
      test "returns the tool status configuration path and config-related link text if there are messages in just one tool" do
        messages = CodeScanning::Status.messages(
          @repository,
          [
            ::Turboscan::Proto::ToolStatus.new(
              name: "CodeQL",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API)
                ),
              ]
            ),
            ::Turboscan::Proto::ToolStatus.new(
              name: "tool-with-messages",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "boom", message: "boom", level: :ATTENTION }, { title: "boomer", message: "boomer", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                  configuration_hash: "abc"
                ),
              ],
            )
          ],
          {},
        )

        component = T.must(messages.error_link_component(@repository))
        render_inline(component)
        assert_link href: "/#{@repository.name_with_owner}/security/code-scanning/tools/tool-with-messages/status/configurations/api/616263", exact_text: "status page"
      end

      test "returns the configuration path of the tool with the highest severity message, and link text referencing it" do
        messages = CodeScanning::Status.messages(
          @repository,
          [
            ::Turboscan::Proto::ToolStatus.new(
              name: "higher-sev-tool",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "danger ", message: "boomer", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                  configuration_hash: "abc"
                ),
              ],
            ),
            ::Turboscan::Proto::ToolStatus.new(
              name: "CodeQL",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "boom", message: "boom", level: :ATTENTION }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                ),
              ],
            ),
          ],
          {},
        )

        component = T.must(messages.error_link_component(@repository))
        render_inline(component)
        assert_link href: "/#{@repository.name_with_owner}/security/code-scanning/tools/higher-sev-tool/status/configurations/api/616263", exact_text: "status page"
      end

      test "returns the configuration path of first tool and link text referencing it if there are 2 tools with the highest severity messages" do
        messages = CodeScanning::Status.messages(
          @repository,
          [
            ::Turboscan::Proto::ToolStatus.new(
              name: "AnotherTool",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "danger ", message: "boomer", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                  configuration_hash: "abc"
                ),
              ],
            ),
            ::Turboscan::Proto::ToolStatus.new(
              name: "YetAnotherTool",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "boom", message: "boomboom", level: :DANGER }, { title: "boomer", message: "boomer", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                ),
              ],
            ),
          ],
          {},
        )

        component = T.must(messages.error_link_component(@repository))
        render_inline(component)
        assert_link href: "/#{@repository.name_with_owner}/security/code-scanning/tools/AnotherTool/status/configurations/api/616263", exact_text: "status page"
      end

      test "for two tools, CodeQL is prioritised for message and link" do
        messages = CodeScanning::Status.messages(
          @repository,
          [
            ::Turboscan::Proto::ToolStatus.new(
              name: "AnotherTool",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "danger ", message: "boomer", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                ),
              ],
            ),
            ::Turboscan::Proto::ToolStatus.new(
              name: "CodeQL",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "boom", message: "boom", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                  configuration_hash: "abc"
                ),
              ],
            ),
          ],
          {},
        )

        component = T.must(messages.error_link_component(@repository))
        render_inline(component)
        # CodeQL prioritised even though it was second in the array
        assert_link href: "/#{@repository.name_with_owner}/security/code-scanning/tools/CodeQL/status/configurations/api/616263", exact_text: "status page"
      end

      test "returns the tool status show path and generic link text if there are more than 2 tools with the highest severity messages" do
        messages = CodeScanning::Status.messages(
          @repository,
          [
            ::Turboscan::Proto::ToolStatus.new(
              name: "AnotherTool",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "danger ", message: "boomer", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                ),
              ],
            ),
            ::Turboscan::Proto::ToolStatus.new(
              name: "CodeQL",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "boom", message: "boom", level: :ATTENTION }, { title: "boomer", message: "boomer", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                ),
              ],
            ),
            ::Turboscan::Proto::ToolStatus.new(
              name: "YetAnotherTool",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "boom", message: "boomboom", level: :ATTENTION }, { title: "boomer", message: "boomer", level: :DANGER }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                ),
              ],
            ),
          ],
          {},
        )

        component = T.must(messages.error_link_component(@repository))
        render_inline(component)
        # The link will be to the status for CodeQL or the first tool if not present.
        # /security/code-scanning/tools/ is something different so we always have to
        # reference a specific tool when linking to the tool status "overview" page.
        assert_link href: "/#{@repository.name_with_owner}/security/code-scanning/tools/CodeQL/status", exact_text: "tool overview page"
      end

      test "returns nil if there are no warning or error messages" do
        messages = CodeScanning::Status.messages(
          @repository,
          [
            ::Turboscan::Proto::ToolStatus.new(
              name: "CodeQL",
              categories: [
                ::Turboscan::Proto::CategoryStatus.new(
                  has_most_recent: true,
                  messages: [{ title: "some suggestin text", message: "a suggestion", level: :SUCCESS }],
                  configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
                ),
              ],
            )
          ],
          {},
        )

        assert_nil messages.error_link_component(@repository)
      end
    end

    test "returns a danger message if a category has not been updated recently for an actions workflow" do
      errors = CodeScanning::Status.messages(
        @repository,
        [
          ::Turboscan::Proto::ToolStatus.new(
            name: "CodeQL",
            categories: [
              ::Turboscan::Proto::CategoryStatus.new(has_most_recent: true, workflow_run_id: 0, updated_at: Google::Protobuf::Timestamp.new(seconds: 1), configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_YML)),
            ],
          ),
        ],
        {},
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "Code Scanning results may be out of date", message.title
      assert_equal CodeScanning::Status::DANGER, message.level
      assert_match /actions workflow logs/, message.message
    end

    test "returns a danger message if a category has never had a successful analysis" do
      errors = CodeScanning::Status.messages(
        @repository,
        [::Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: [::Turboscan::Proto::CategoryStatus.new(has_most_recent: false, updated_at: Google::Protobuf::Timestamp.new(seconds: 10.seconds.ago.to_i), configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API))])],
        {},
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "No code scanning results", message.title
      assert_equal CodeScanning::Status::DANGER, message.level
    end

    test "returns a danger message if a category has not been updated recently for an API upload" do
      errors = CodeScanning::Status.messages(
        @repository,
        [::Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: [::Turboscan::Proto::CategoryStatus.new(has_most_recent: true, updated_at: Google::Protobuf::Timestamp.new(seconds: 1), configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API))])],
        {},
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "Code Scanning results may be out of date", message.title
      assert_equal CodeScanning::Status::DANGER, message.level
      refute_match /actions workflow logs/, message.message
    end

    test "returns a danger message if a category has failed processing for an actions workflow" do
      errors = CodeScanning::Status.messages(
        @repository,
        [::Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: [::Turboscan::Proto::CategoryStatus.new(has_most_recent: true, workflow_run_id: 0, analysis_status: :FAILED, configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_YML))])],
        {},
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "Code Scanning failed", message.title
      assert_equal CodeScanning::Status::DANGER, message.level
      assert_match /actions workflow logs/, message.message
    end

    test "returns a danger message if a category has failed processing for an API upload" do
      errors = CodeScanning::Status.messages(
        @repository,
        [::Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: [::Turboscan::Proto::CategoryStatus.new(has_most_recent: true, analysis_status: :FAILED, configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API))])],
        {},
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "Code Scanning failed", message.title
      assert_equal CodeScanning::Status::DANGER, message.level
      refute_match /actions workflow logs/, message.message
    end

    test "returns an attention message if a category has not been updated recently, but there exists another that has" do
      errors = CodeScanning::Status.messages(
        @repository,
        [
          ::Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: [
            ::Turboscan::Proto::CategoryStatus.new(has_most_recent: true, workflow_run_id: 0, updated_at: Google::Protobuf::Timestamp.new(seconds: 1), configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API)),
            ::Turboscan::Proto::CategoryStatus.new(has_most_recent: true, workflow_run_id: 0, updated_at: Google::Protobuf::Timestamp.new(seconds: 10.seconds.ago.to_i), configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API)),
          ]),
        ],
        {},
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "Code Scanning results may be out of date", message.title
      assert_equal CodeScanning::Status::ATTENTION, message.level
    end

    test "returns a danger message if a category has failed the most recent run for an actions workflow" do
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app, :with_push, repository: @repository)
      check_run = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", name: "test")
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)
      ref = @repository.heads.find_or_build(@repository.default_branch)
      ref.append_commit({ committer: @user, message: "Add a workflow." }, @user) do |files|
        files.add(workflow_run.workflow.path, <<~YAML
          on: [push]
          YAML
        )
      end

      errors = CodeScanning::Status.messages(
        @repository,
        [
          ::Turboscan::Proto::ToolStatus.new(
            name: "CodeQL",
            categories: [
              ::Turboscan::Proto::CategoryStatus.new(
                workflow_run_id: 49382,
                configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(
                  delivery_origin: :DELIVERY_ORIGIN_YML,
                  workflow_path: workflow_run.workflow.path,
                ),
                has_most_recent: true,
              ),
            ],
          ),
        ],
        CodeScanning::Status.fetch_workflows(@repository, [workflow_run.workflow.path]),
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "Workflow runs failing", message.title
      assert_equal CodeScanning::Status::DANGER, message.level
      assert_match /most recent run for this workflow failed/, message.message
      a, = HTML::Pipeline.parse(message.action).children
      assert_equal workflow_run.id.to_s, a.attributes["href"].value.split("/").last
    end

    test "returns a danger message if a category has timed out the most recent run for an actions workflow" do
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app, :with_push, repository: @repository)
      check_run = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "timed_out", name: "test")
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)
      ref = @repository.heads.find_or_build(@repository.default_branch)
      ref.append_commit({ committer: @user, message: "Add a workflow." }, @user) do |files|
        files.add(workflow_run.workflow.path, <<~YAML
          on: [push]
        YAML
        )
      end

      errors = CodeScanning::Status.messages(
        @repository,
        [
          ::Turboscan::Proto::ToolStatus.new(
            name: "CodeQL",
            categories: [
              ::Turboscan::Proto::CategoryStatus.new(
                workflow_run_id: 49382,
                configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(
                  delivery_origin: :DELIVERY_ORIGIN_YML,
                  workflow_path: workflow_run.workflow.path,
                  ),
                has_most_recent: true,
                ),
            ],
            ),
        ],
        CodeScanning::Status.fetch_workflows(@repository, [workflow_run.workflow.path]),
        )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "Workflow runs failing", message.title
      assert_equal CodeScanning::Status::DANGER, message.level
      assert_match /most recent run for this workflow failed/, message.message
      a, = HTML::Pipeline.parse(message.action).children
      assert_equal workflow_run.id.to_s, a.attributes["href"].value.split("/").last
    end

    test "does not pay attention to workflow runs on forks" do
      make_trusted_oauth_apps_owner
      workflow_path = ".github/workflows/codeql-analysis.yml"
      ref = @repository.heads.find_or_build(@repository.default_branch)
      ref.append_commit({ committer: @user, message: "Add a workflow." }, @user) do |files|
        files.add(workflow_path, <<~YAML
          on: [push]
          YAML
        )
      end
      @repository.owner.allow_private_repository_forking(force: true, actor: @user, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
      fork_repository = create(:fork_repository, forker: @user, fork_repo: @repository)
      check_suite = create(:check_suite_for_actions_app, :with_push, repository: @repository, head_repository: fork_repository, workflow_file_path: workflow_path)
      check_run = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", name: "test")
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)

      errors = CodeScanning::Status.messages(
        @repository,
        [
          ::Turboscan::Proto::ToolStatus.new(
            name: "CodeQL",
            categories: [
              ::Turboscan::Proto::CategoryStatus.new(
                workflow_run_id: 49382,
                configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(
                  delivery_origin: :DELIVERY_ORIGIN_YML,
                  workflow_path: workflow_run.workflow.path,
                ),
                has_most_recent: true,
              ),
            ],
          ),
        ],
        CodeScanning::Status.fetch_workflows(@repository, [workflow_run.workflow.path]),
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 0, messages.size
    end

    test "adds location action to messages" do
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app, :with_push, repository: @repository)
      check_run = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", name: "test")
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)
      ref = @repository.heads.find_or_build(@repository.default_branch)
      ref.append_commit({ committer: @user, message: "Add a workflow." }, @user) do |files|
        files.add(workflow_run.workflow.path, <<~YAML
          on: [push]
          YAML
        )
      end

      errors = CodeScanning::Status.messages(
        @repository,
        [
          ::Turboscan::Proto::ToolStatus.new(
            name: "CodeQL",
            categories: [
              ::Turboscan::Proto::CategoryStatus.new(
                workflow_run_id: 49382,
                configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(
                  delivery_origin: :DELIVERY_ORIGIN_YML,
                  workflow_path: workflow_run.workflow.path,
                ),
                messages: [Turboscan::Proto::AnalysisMessage.new({
                  locations: [Turboscan::Proto::Location.new(file_path: "bar.js")],
                })],
                has_most_recent: true,
              ),
            ],
          ),
        ],
        CodeScanning::Status.fetch_workflows(@repository, [workflow_run.workflow.path]),
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_equal 1, messages.size
      message = T.must(messages.first)
      a, = HTML::Pipeline.parse(message.action).children
      assert_match %r"/bar\.js$", a.attributes["href"].value
    end

    test "returns no errors if a category has succeeded the most recent run for an actions workflow" do
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app, :with_push, repository: @repository)
      check_run = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", name: "test")
      workflow_run = check_suite.workflow_run
      make_searchable(workflow_run)

      errors = CodeScanning::Status.messages(
        @repository,
        [
          ::Turboscan::Proto::ToolStatus.new(
            name: "CodeQL",
            categories: [
              ::Turboscan::Proto::CategoryStatus.new(
                workflow_run_id: 49382,
                configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(
                  delivery_origin: :DELIVERY_ORIGIN_YML,
                  workflow_path: workflow_run.workflow.path,
                ),
                has_most_recent: true,
              ),
            ],
          ),
        ],
        {
          workflow_run.workflow.path => CodeScanning::Status::Workflow.new(
            path: workflow_run.workflow.path,
            name: "CodeQL",
            state: "active",
            schedule: nil,
            events: nil,
          ),
        },
      )
      refute_nil errors
      messages = errors.fetch("CodeQL")
      refute_nil messages
      assert_empty messages
    end
  end

  test "returns an error if the actions workflow has been set to inactive" do
    make_trusted_oauth_apps_owner
    check_suite = create(:check_suite_for_actions_app, :with_push, repository: @repository)
    check_run = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", name: "test")
    workflow_run = check_suite.workflow_run
    make_searchable(workflow_run)

    errors = CodeScanning::Status.messages(
      @repository,
      [
        ::Turboscan::Proto::ToolStatus.new(
          name: "CodeQL",
          categories: [
            ::Turboscan::Proto::CategoryStatus.new(
              workflow_run_id: 49382,
              configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(
                delivery_origin: :DELIVERY_ORIGIN_YML,
                workflow_path: workflow_run.workflow.path,
              ),
              has_most_recent: true,
            ),
          ],
        ),
      ],
      {
        workflow_run.workflow.path => CodeScanning::Status::Workflow.new(
          path: workflow_run.workflow.path,
          name: "CodeQL",
          state: "disabled_manually",
          schedule: nil,
          events: nil,
        ),
      },
    )
    refute_nil errors
    messages = errors.fetch("CodeQL")
    refute_empty messages
    assert_equal "Actions workflow not enabled", messages[0]&.title
  end

  sig do
    params(
      items: T::Hash[String, T::Array[Turboscan::Proto::AnalysisMessageLevel]],
    ).returns(CodeScanning::Status::Messages)
  end
  def messages_for_tools_and_levels(items)
    tools = items.map do |name, levels|
      Turboscan::Proto::ToolStatus.new({
        name: name,
        categories: [
          Turboscan::Proto::CategoryStatus.new({
            has_most_recent: true,
            messages: levels.map do |level|
              Turboscan::Proto::AnalysisMessage.new({
                level: level,
              })
            end,
            configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(
              delivery_origin: :DELIVERY_ORIGIN_YML,
            ),
          }),
        ],
      })
    end

    CodeScanning::Status.messages(@repository, tools, {})
  end

  context "::CodeScanning::Status.max_level" do
    test "returns success if no messages for tool" do
      messages = messages_for_tools_and_levels("CodeQL" => [])

      assert_equal CodeScanning::Status::SUCCESS, ::CodeScanning::Status.max_level(messages.fetch("CodeQL"))
    end

    test "raises KeyError if tool not found" do
      messages = messages_for_tools_and_levels("Not Found" => [])

      assert_raises KeyError do
        messages.fetch("CodeQL")
      end
    end

    test "returns level of single message if just one for tool" do
      messages = messages_for_tools_and_levels("CodeQL" => [Turboscan::Proto::AnalysisMessageLevel::ATTENTION])

      assert_equal CodeScanning::Status::ATTENTION, ::CodeScanning::Status.max_level(messages.fetch("CodeQL"))
    end

    test "returns most severe if multiple messages for tool, even if that's not the first message" do
      messages = messages_for_tools_and_levels(
        "CodeQL" => [
          CodeScanning::Status::ATTENTION,
          CodeScanning::Status::DANGER,
          CodeScanning::Status::SUCCESS,
        ]
      )

      assert_equal CodeScanning::Status::DANGER, ::CodeScanning::Status.max_level(messages.fetch("CodeQL"))
    end
  end

  context "validate_prerequisites" do
    test "returns no errors if all prerequisites are met" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)
      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group", runners: [self_hosted_runner_with_labels("code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options)

      assert_nil error
    end

    test "returns no errors if all prerequisites are met with runner scale sets" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)

      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group",
        runner_scale_sets: [runner_scale_set_with_labels("code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])
      Actions::RunnerGroup.stubs(:get).returns(runner_group)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options)

      assert_nil error
    end

    test "returns no errors if all prerequisites are met with individually assigned runners" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)
      Actions::RunnerGroup.stubs(:for_entity).returns([])

      if GitHub.enterprise?
        resp = GitHub::Launch::Services::Selfhostedrunners::ListRunnersResponse.new(
          runners: [self_hosted_runner_with_labels("code-scanning")],
          total_runners: 1,
        )
        mock_list_runners(owner: @repository, status: 200, response: resp)
      end

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options)

      assert_nil error
    end

    test "returns no errors if all prerequisites are met with individually assigned runner scale sets" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)
      Actions::RunnerScaleSet.stubs(:for_entity).returns([runner_scale_set_with_labels("code-scanning")])

      if GitHub.enterprise?
        resp = GitHub::Launch::Services::Selfhostedrunners::ListRunnersResponse.new(runners: [], total_runners: 0)
        mock_list_runners(owner: @repository, status: 200, response: resp)
      end

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options)

      assert_nil error
    end

    test "returns no errors if all prerequisites are met with 'macOS' runner when swift is being enabled with ff on" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)

      @repository.update(languages: [@swift, @ruby])
      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group",
        runner_scale_sets: [runner_scale_set_with_labels("macOS", "code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])
      Actions::RunnerGroup.stubs(:get).returns(runner_group)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options)

      assert_nil error
    end

    test "returns an error when there's no 'macOS' runner and only swift is being enabled, but only if we are targetting default setup prerequisites in the validation", enterprise_only: true do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)

      @repository.update(languages: [@swift])
      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group",
        runner_scale_sets: [runner_scale_set_with_labels("not-macOS-label", "code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])
      Actions::RunnerGroup.stubs(:get).returns(runner_group)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options.merge(languages: ["swift"], runner_label: "code-scanning"))

      assert_equal :no_macos_runners_assigned, error

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: { languages: ["swift"] })

      assert_nil error
    end

    test "returns no error when there's no 'macOS' runner and swift is not the only language being enabled", enterprise_only: true do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)

      @repository.update(languages: [@swift, @ruby])
      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group",
        runner_scale_sets: [runner_scale_set_with_labels("not-macOS-label", "code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])
      Actions::RunnerGroup.stubs(:get).returns(runner_group)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options.merge(languages: %w[swift ruby]))

      assert_nil error
    end

    test "returns no error when there's no 'macOS' runner when swift is being enabled in dotcom", skip_enterprise: true do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)

      @repository.update(languages: [@swift, @ruby])
      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group",
        runner_scale_sets: [runner_scale_set_with_labels("not-macOS-label", "code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])
      Actions::RunnerGroup.stubs(:get).returns(runner_group)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options.merge(languages: ["swift"]))

      assert_nil error
    end

    test "returns error if repo is archived" do
      @repository.set_archived
      error = CodeScanning::Status.validate_prerequisites(@repository, @user)

      assert_equal error, :repo_archived
    end

    test "returns error if advanced security not enabled" do
      # Explicitly show that GHAS is not enabled
      assert !SecurityProduct::AdvancedSecurity.new(@repository).enabled?

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)

      assert_equal error, :advanced_security_disabled
    end

    test "returns no error if Advanced Security is not enabled but option to skip ghas check supplied" do
      # Explicitly show that GHAS is not enabled
      assert !SecurityProduct::AdvancedSecurity.new(@repository).enabled?

      GitHub.stubs(:actions_enabled?).returns(true)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: { skip_ghas_check?: true })

      assert_nil error
    end

    test "returns error if Code Scaning is not available" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:code_scanning_enabled?).returns(false)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)

      assert_equal error, :code_scanning_not_available
    end

    test "returns error if Actions is not yet set up and site admin" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(false)
      become_github_staff(@user)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)
      assert_equal error, :instance_actions_disabled_admin
    end

    test "returns error if Actions is not yet set up and in cluster mode" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(false)
      GitHub.stubs(:cluster_regular_enabled?).returns(true)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)

      assert_equal error, :instance_actions_disabled
    end

    test "returns error if Actions is not yet set up and not site admin" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(false)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)
      assert_equal error, :instance_actions_disabled
    end

    test "returns error if Actions is disabled by policy" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      @owner.disable_actions(actor: @user)
      @repository.reload

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)
      assert_equal error, :repo_actions_disabled_by_owner
    end

    test "returns error if Actions is disabled by repository" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      @repository.disable_actions(actor: @user)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)
      assert_equal error, :repo_actions_disabled
    end

    test "returns error if Actions is disabled because repository was forked" do
      ref = @repository.heads.find_or_build(@repository.default_branch)
      ref.append_commit({ committer: @user, message: "Add a workflow." }, @user) do |files|
        files.add(".github/workflows/no-name.yml", <<~YAML
          on: [push]
          YAML
        )
      end
      fork_owner = build(:organization)
      fork_owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      fork_owner.add_member(@user)
      @repository.owner.allow_private_repository_forking(force: true, actor: @user, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
      fork_repository, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @repository.fork(forker: @user, org: fork_owner) }
      assert_equal :created, status
      fork_repository.enable_advanced_security!(actor: @user)
      make_trusted_oauth_apps_owner
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      error = CodeScanning::Status.validate_prerequisites(fork_repository, @user)

      assert_equal error, :fork_actions_disabled
    end

    test "returns error if there are no runners assigned to the repository" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)

      if GitHub.enterprise?
        resp = GitHub::Launch::Services::Selfhostedrunners::ListRunnersResponse.new(runners: [], total_runners: 0)
        mock_list_runners(owner: @repository, status: 200, response: resp)
      end

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options)

      if GitHub.enterprise?
        assert_equal error, :no_runners_assigned
      else
        assert_nil error
      end
    end

    test "returns error if there are no runners with code scanning label assigned to the repository" do
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)
      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group", runners: [self_hosted_runner_with_labels("not-code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])
      Actions::RunnerGroup.stubs(:get).returns(runner_group)

      if GitHub.enterprise?
        resp = GitHub::Launch::Services::Selfhostedrunners::ListRunnersResponse.new(runners: [], total_runners: 0)
        mock_list_runners(owner: @repository, status: 200, response: resp)
      end

      error = CodeScanning::Status.validate_prerequisites(@repository, @user, options: @default_setup_validation_options)

      if GitHub.enterprise?
        assert_equal error, :no_runners_assigned
      else
        assert_nil error
      end
    end

    # for now we don't check on GHES
    test "returns error if there is one pattern but not all of them", skip_enterprise: true do
      # Fulfil all the criteria for code scanning to be enabled
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)

      # Add just one pattern to the allow list
      allowlist = create(:actions_policy_allowlist, entity: @repository)
      create(:allowed_action_pattern, allowlist: allowlist, value: "actions/*")
      Repository.any_instance.stubs(:can_use_actions_allowlist?).returns(true)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)

      assert_equal error, :actions_policy_disabled
    end

    # for now we don't check on GHES
    test "does not return an error when both patterns are present at repository level", skip_enterprise: true do
      # Fulfil all the criteria for code scanning to be enabled
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)

      # Add both patterns to the allow list
      allowlist = create(:actions_policy_allowlist, entity: @repository)
      create(:allowed_action_pattern, allowlist: allowlist, value: "actions/*")
      create(:allowed_action_pattern, allowlist: allowlist, value: "github/*")
      Repository.any_instance.stubs(:can_use_actions_allowlist?).returns(true)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)

      assert_nil error
    end

    # for now we don't check on GHES
    test "does not return an error when both patterns are present at organization level", skip_enterprise: true do
      # Fulfil all the criteria for code scanning to be enabled
      @owner.mark_advanced_security_as_purchased_for_entity(actor: @user)
      @repository.enable_advanced_security!(actor: @user)
      GitHub.stubs(:actions_enabled?).returns(true)
      Repository.any_instance.stubs(:owner_can_use_actions_enterprise_features?).returns(true)

      # Add both patterns to the allow list
      allowlist = create(:actions_policy_allowlist, entity: @owner)
      create(:allowed_action_pattern, allowlist: allowlist, value: "actions/*")
      create(:allowed_action_pattern, allowlist: allowlist, value: "github/*")
      Organization.any_instance.stubs(:can_use_actions_allowlist?).returns(true)

      error = CodeScanning::Status.validate_prerequisites(@repository, @user)

      assert_nil error
    end
  end

  context "#mac_os_runner?" do
    test "returns true on dotcom", skip_enterprise: true do
      assert CodeScanning::Status.mac_os_runner?(repository: @repository)
    end

    test "returns true if the runner is mac-os" do
      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group", runners: [self_hosted_runner_with_labels("macOS", "code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])

      assert CodeScanning::Status.mac_os_runner?(repository: @repository)
    end

    test "returns false if the runner is not mac-os on GHES", enterprise_only: true do
      runner_group = Actions::RunnerGroup.new(id: 1, name: "Runner Group",
        runner_scale_sets: [runner_scale_set_with_labels("I-am-not-macOS", "code-scanning")])
      Actions::RunnerGroup.stubs(:for_entity).returns([runner_group])
      Actions::RunnerGroup.stubs(:get).returns(runner_group)

      resp = GitHub::Launch::Services::Selfhostedrunners::ListRunnersResponse.new(runners: [], total_runners: 0)
      mock_list_runners(owner: @repository, status: 200, response: resp)

      refute CodeScanning::Status.mac_os_runner?(repository: @repository)
    end
  end

  private

  def self_hosted_runner_with_labels(*labels)
    runner_labels = labels.map { |label| self_hosted_runner_label(label: label) }
    GitHub::Launch::Services::Selfhostedrunners::Runner.new(labels: runner_labels)
  end

  def self_hosted_runner_label(label:)
    GitHub::Launch::Services::Selfhostedrunners::Label.new(name: label)
  end

  def runner_scale_set_with_labels(*labels)
    runner_labels = labels.map { |label| runner_scale_set_label(label: label) }
    GitHub::Launch::Services::Runnerscalesets::RunnerScaleSet.new(labels: runner_labels)
  end

  def runner_scale_set_label(label:)
    GitHub::Launch::Services::Runnerscalesets::Label.new(name: label)
  end

  # emit_tool_status_hydro_event is tested in the "hydro" context in
  # test/integration/repos/code_scanning/tool_status_controller_test.rb.
  # and in test/lib/github/stream_processors/code_scanning_processed_analysis_test.rb
end
