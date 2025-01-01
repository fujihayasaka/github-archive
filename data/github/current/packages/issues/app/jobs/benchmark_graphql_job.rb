# typed: false
# frozen_string_literal: true
require "scientist"
require "graphql"
require "opentelemetry/instrumentation/graphql/tracers/graphql_tracer"

class BenchmarkGraphqlJob < ApplicationJob
  class SimpleSchema < GraphQL::Schema # rubocop:disable Rails/ModuleNaming
    class User < GraphQL::Schema::Object # rubocop:disable Rails/ModuleNaming
      field :login, String
    end

    class Label < GraphQL::Schema::Object # rubocop:disable Rails/ModuleNaming
      field :name, String
      field :color, String
    end

    class Issue < GraphQL::Schema::Object # rubocop:disable Rails/ModuleNaming
      field :id, String
      def id
        object.global_relay_id
      end

      field :title, String
      field :body, String
      def body
        object.body || ""
      end
      field :body_html, String
      def body_html
        # bust the cache
        object.instance_variable_set("@body_result_cache", nil)
        object.async_body_html(context: {}).sync
      end

      field :labels, Label.connection_type, scope: true
      def labels
        object.labels
      end

      field :assignees, User.connection_type
      def assignees
        object.assignees
      end
    end

    class Repository < GraphQL::Schema::Object # rubocop:disable Rails/ModuleNaming
      field :issue, Issue, null: true do
        argument :number, Integer, required: true
      end
      def issue(number:)
        issue = object.issues.find_by(number: number)
        return nil unless issue&.readable_by?(context[:viewer])
        issue
      end
    end

    class Query < GraphQL::Schema::Object # rubocop:disable Rails/ModuleNaming
      field :repository, Repository, description: "Lookup a given repository by the owner and repository name.", null: true do
        argument :owner, String, "The login field of a user or organization", required: true
        argument :name, String, "The name of the repository", required: true
      end

      def repository(owner:, name:)
        owner = ::User.find_by_login(owner)
        return nil unless owner
        repo = owner.repositories.find_by(name: name)
        return nil unless repo&.readable_by?(context[:viewer])
        repo
      end
    end

    query(Query)
  end

  class CustomSchema < Platform::Schema
    def self.tracers
      []
    end
  end

  class FakeQueryTracker < Platform::QueryTracker
    def track
      yield
    end
  end

  include Scientist
  include PlatformHelper

  queue_as :benchmark_graphql

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  ShowQueryString = <<-'GRAPHQL'
    query($repoOwner: String!, $repoName: String!, $number: Int!) {
      repository(owner: $repoOwner, name: $repoName) {
        issue(number: $number) {
          id,
          title,
          body,
          labels(first: 100) {
            edges {
              node {
                name,
              }
            }
          }
          assignees(first: 100) {
            edges {
              node {
                login
              }
            }
          }
        }
      }
    }
  GRAPHQL

  CpuHeavyShowQueryString = <<-'GRAPHQL'
    query($repoOwner: String!, $repoName: String!, $number: Int!) {
      repository(owner: $repoOwner, name: $repoName) {
        issue(number: $number) {
          body1: bodyHtml,
          body2: bodyHtml,
          body3: bodyHtml,
          body4: bodyHtml,
          body5: bodyHtml,
          body6: bodyHtml,
          body7: bodyHtml,
          body8: bodyHtml,
          body9: bodyHtml,
          body10: bodyHtml,
          id,
          title,
          body,
          labels(first: 100) {
            edges {
              node {
                name,
              }
            }
          }
          assignees(first: 100) {
            edges {
              node {
                login
              }
            }
          }
        }
      }
    }
  GRAPHQL

  ObjectHeavyShowQueryString = <<-'GRAPHQL'
    query(
      $repoOwner: String!,
      $repoName: String!,
      $number1: Int!,
      $number2: Int!,
      $number3: Int!,
      $number4: Int!,
      $number5: Int!,
      $number6: Int!,
      $number7: Int!,
      $number8: Int!,
      $number9: Int!,
      $number10: Int!,
      ) {
      repository(owner: $repoOwner, name: $repoName) {
        issue1: issue(number: $number1) {
          ...IssueFragment
        }
        issue2: issue(number: $number2) {
          ...IssueFragment
        }
        issue3: issue(number: $number3) {
          ...IssueFragment
        }
        issue4: issue(number: $number4) {
          ...IssueFragment
        }
        issue5: issue(number: $number5) {
          ...IssueFragment
        }
        issue6: issue(number: $number6) {
          ...IssueFragment
        }
        issue7: issue(number: $number7) {
          ...IssueFragment
        }
        issue8: issue(number: $number8) {
          ...IssueFragment
        }
        issue9: issue(number: $number9) {
          ...IssueFragment
        }
        issue10: issue(number: $number10) {
          ...IssueFragment
        }
      }
    }

    fragment IssueFragment on Issue {
      id,
      title,
      body,
      labels(first: 100) {
        edges {
          node {
            name,
          }
        }
      }
      assignees(first: 100) {
        edges {
          node {
            login
          }
        }
      }
    }
  GRAPHQL

  ShowQuery = PlatformHelper::PlatformClient.parse ShowQueryString

  IndexQueryString = <<-'GRAPHQL'
    query($first: Int!, $query: String!, $owner: String!, $repo: String!) {
      search(first: $first, query: $query, type: ISSUE) {
        edges {
          node {
            ... on Issue {
              __typename
              id
              databaseId
              number
              title
              titleHTML
              author {
                __typename
                id
                login
              }
              state
              stateReason
              isReadByViewer
              repository {
                id
                name
                nameWithOwner
              }
              labels(first: 100) {
                edges {
                  node {
                    id
                    name
                    description
                    color
                  }
                }
              }
              assignees(first: 100) {
                edges {
                  node {
                    __typename
                    id
                    login
                  }
                }
              }
            }
          }
        }
        issueCount
      }
      repository(owner: $owner, name: $repo) {
        id
        viewerCanPush
        isDisabled
        isLocked
        isArchived
      }
      viewer {
        __typename
        id
        login
      }
    }
  GRAPHQL

  IndexQuery = PlatformHelper::PlatformClient.parse IndexQueryString
  def perform(actor_id, repo_id, issue_number)
    @viewer = User.find_by(id: actor_id)
    return nil unless @viewer

    @repo_id = repo_id

    repo = Repository.find_by(id: @repo_id)
    return unless repo

    @repo_owner = repo.owner&.display_login
    @repo_name = repo.name

    @issue_number = issue_number

    if @issue_number
      benchmark_show
    else
      benchmark_index
    end
  end

  def benchmark_show
    science "graphql_benchmark_show" do |e|
      e.use do
        track_perf("show", "custom") do
          show_custom
        end
      end
      e.try do
        track_perf("show", "graphql") do
          show_graphql
        end
      end
    end

    science "graphql_benchmark_show_with_minimal_schema" do |e|
      e.use do
        track_perf("show", "custom") do
          show_custom
        end
      end
      e.try do
        track_perf("show", "graphql_minimal_schema") do
          show_graphql_with_minimal_schema
        end
      end
    end

    science "graphql_benchmark_show_with_minimal_schema_cpu_heavy" do |e|
      e.use do
        track_perf("show", "custom_cpu_heavy") do
          show_custom(run_cpu_heavy: true)
        end
      end
      e.try do
        track_perf("show", "graphql_minimal_schema_cpu_heavy") do
          show_graphql_with_minimal_schema(run_cpu_heavy: true)
        end
      end
    end

    issues = Issue.where(repository_id: @repo_id).order(created_at: :desc).limit(10)
    all_issues_readable = issues.all? { |issue| issue.readable_by?(@viewer) }
    issue_numbers = issues.map(&:number)
    if issue_numbers.size == 10 && all_issues_readable
      science "graphql_benchmark_show_with_minimal_schema_object_heavy" do |e|
        e.use do
          track_perf("show", "custom_object_heavy") do
            show_custom_object_heavy(issue_numbers)
          end
        end
        e.try do
          track_perf("show", "graphql_minimal_schema_object_heavy") do
            show_graphql_with_minimal_schema_object_heavy(issue_numbers)
          end
        end
      end
    end
  end

  def show_custom_object_heavy(issues)
    result = []
    owner = User.find_by_login(@repo_owner)
    repo = owner.repositories.find_by(name: @repo_name)
    return result unless repo&.readable_by?(@viewer)

    issues.each do |issue_number|
      @issue_number = issue_number
      response = show_custom(run_cpu_heavy: false, repo: repo)
      result << response["repository"]["issue"]["id"]
    end
    result
  end

  def show_graphql_with_minimal_schema_object_heavy(issues)
    variables = {
      repoOwner: @repo_owner,
      repoName: @repo_name,
    }
    issues.each_with_index do |issue_number, index|
      variables["number#{index + 1}"] = issue_number
    end

    response = SimpleSchema.execute(ObjectHeavyShowQueryString, variables: variables, context: { viewer: @viewer })

    data = response.to_h["data"]
    result = []
    array = (1..10).to_a
    array.each do |i|
      result << data["repository"]["issue#{i}"]["id"]
    end
    result
  end

  def show_custom(run_cpu_heavy: false, repo: nil)
    unless repo
      owner = User.find_by_login(@repo_owner)
      repo = owner.repositories.find_by(name: @repo_name)
      default_response = {
        "repository" => nil
      }

      return default_response unless repo&.readable_by?(@viewer)
    end

    default_response = {
      "repository" => {
        "issue" => nil
      }
    }

    issue = repo.issues.find_by(number: @issue_number)
    return default_response unless issue&.readable_by?(@viewer)

    labels = issue.labels.map(&:name).sort
    assignees = issue.assignees.map(&:display_login).sort

    if run_cpu_heavy && issue
      array = (1..10).to_a
      array.each do
        issue.async_body_html(context: {}).sync
        issue.instance_variable_set("@body_result_cache", nil)
      end
    end

    {
      "repository" => {
        "issue" => {
          "id" => issue.global_relay_id,
          "title" => issue.title,
          "body" => issue.body || "",
          "labels" => {
            "edges" => labels.map do |label|
              {
                "node" => {
                  "name" => label
                }
              }
            end
          },
          "assignees" => {
            "edges" => assignees.map do |assignee|
              {
                "node" => {
                  "login" => assignee
                }
              }
            end
          }
        }
      }
    }
  end

  def sort_lists(data)
    if data["repository"] && data["repository"]["issue"]
      data["repository"]["issue"]["labels"]["edges"] = data["repository"]["issue"]["labels"]["edges"].sort_by { |edge| edge["node"]["name"] }
    end
    if data["repository"] && data["repository"]["issue"]
      data["repository"]["issue"]["assignees"]["edges"] = data["repository"]["issue"]["assignees"]["edges"].sort_by { |edge| edge["node"]["login"] }
    end
    data
  end

  def show_graphql_with_minimal_schema(run_cpu_heavy: false)
    variables = {
      repoOwner: @repo_owner,
      repoName: @repo_name,
      number: @issue_number
    }

    query_string = run_cpu_heavy ? CpuHeavyShowQueryString : ShowQueryString
    response = SimpleSchema.execute(query_string, variables: variables, context: { viewer: @viewer })

    data = response.to_h["data"]
    data = sort_lists(data)

    # remove all body html fields becuase the cause mismatches due to token in image urls
    if run_cpu_heavy && data["repository"] && data["repository"]["issue"]
      array = (1..10).to_a
      array.each do |i|
        data["repository"]["issue"].delete("body#{i}")
      end
    end
    data
  end

  def show_graphql
    context = { viewer: @viewer }
    variables = {
      repoOwner: @repo_owner,
      repoName: @repo_name,
      number: @issue_number
    }

    response = Platform.execute(
      ShowQueryString,
      target: :internal,
      variables: variables,
      context: context,
    )

    data = response.data.to_h.to_hash
    sort_lists(data)
  end

  def benchmark_index
    # make sure the config is the same that is being used for web unicorns where platform tracing is enabled
    OpenTelemetry::Instrumentation::GraphQL::Instrumentation.instance.config[:enable_platform_field] = true
    OpenTelemetry::Instrumentation::GraphQL::Instrumentation.instance.config[:enable_platform_authorized] = true
    OpenTelemetry::Instrumentation::GraphQL::Instrumentation.instance.config[:enable_platform_resolve_type] = true

    science "graphql_benchmark_index" do |e|
      e.use do
        clear_caches
        track_perf("index", "custom") do
          index_custom
        end
      end
      e.try do
        clear_caches
        track_perf("index", "graphql") do
          index_graphql
        end
      end
      e.compare do |control, candidate|
        compare_results(control, candidate)
      end
    end

    science "graphql_benchmark_index_no_tracer" do |e|
      e.use do
        clear_caches
        track_perf("index", "graphql") do
          index_graphql
        end
      end
      e.try do
        clear_caches
        track_perf("index", "graphql_no_tracer") do
          index_graphql_no_tracer
        end
      end
      e.compare do |control, candidate|
        compare_results(control, candidate)
      end
    end

    science "graphql_benchmark_index_no_tracker" do |e|
      e.use do
        clear_caches
        track_perf("index", "graphql") do
          index_graphql
        end
      end
      e.try do
        clear_caches
        track_perf("index", "graphql_no_tracker") do
          index_graphql_no_tracker
        end
      end
      e.compare do |control, candidate|
        compare_results(control, candidate)
      end
    end

    science "graphql_benchmark_index_no_auth" do |e|
      e.use do
        clear_caches
        track_perf("index", "graphql") do
          index_graphql
        end
      end
      e.try do
        clear_caches
        track_perf("index", "graphql_no_auth") do
          index_graphql_no_auth
        end
      end
      e.compare do |control, candidate|
        compare_results(control, candidate)
      end
    end

    science "graphql_benchmark_index_no_execute" do |e|
      e.use do
        clear_caches
        track_perf("index", "graphql") do
          index_graphql
        end
      end
      e.try do
        clear_caches
        track_perf("index", "graphql_no_execute") do
          index_graphql_no_execute
        end
      end
      e.compare do |control, candidate|
        compare_results(control, candidate)
      end
    end

    science "graphql_benchmark_index_no_auth_no_tracer_no_tracker_no_execute" do |e|
      e.use do
        clear_caches
        track_perf("index", "graphql") do
          index_graphql
        end
      end
      e.try do
        clear_caches
        track_perf("index", "graphql_no_auth_no_tracer_no_tracker_no_execute") do
          index_graphql_no_auth_no_tracer_no_tracker_no_execute
        end
      end
      e.compare do |control, candidate|
        compare_results(control, candidate)
      end
    end
  end

  def index_custom
    owner = User.find_by_login(@repo_owner)
    repo = owner.repositories.find_by(name: @repo_name)

    return nil unless repo

    return unless repo.readable_by?(@viewer)

    results = Search::Queries::IssueQuery.new(
      current_user: @viewer,
      phrase: "is:issue state:open repo:#{@repo_owner}/#{@repo_name} sort:created-desc",
      per_page: 25
    ).execute

    issue_ids = results.map { |r| r["_id"].to_i }
    issues = Issue.where(id: issue_ids).includes(:labels, :assignees, :user, :repository).order(created_at: :desc).to_a
    GitHub::PrefillAssociations.prefill_batch_method(issues, :is_read_by_viewer, @viewer)

    res = {
      search: {
        edges: issues.map do |issue|
          {
            node: {
              "__typename": "Issue",
              id: issue.global_relay_id,
              databaseId: issue.id,
              number: issue.number,
              title: issue.title,
              titleHTML: GitHub::Goomba::TitleMarkdownFilter.call(issue.title),
              author: {
                "__typename": T.must(issue.user.class.name),
                id: T.must(issue.user).global_relay_id,
                login: T.must(issue.user).display_login,
              },
              state: T.must(issue.state).upcase,
              stateReason: issue.state_reason&.upcase,
              isReadByViewer: issue.is_read_by_viewer(@viewer),
              repository: {
                id: T.must(issue.repository).global_relay_id,
                name: T.must(issue.repository).name,
                nameWithOwner: T.must(issue.repository).nwo # rubocop:disable GitHub/DoNotAllowNameWithOwner
              },
              labels: {
                edges: issue.labels.map do |label|
                  {
                    node: {
                      id: label.global_relay_id,
                      name: label.name,
                      description: label.description,
                      color: label.color
                    }
                  }
                end
              },
              assignees: {
                edges: issue.assignees.map do |assignee|
                  {
                    node: {
                      "__typename": T.must(assignee.class.name),
                      id: assignee.global_relay_id,
                      login: assignee.login # rubocop:disable GitHub/DoNotAllowLogin
                    }
                  }
                end
              },
            }
          }
        end,
        issueCount: results.count,
      },
      repository: {
        id: repo.global_relay_id,
        viewerCanPush: repo.async_pushable_by?(@viewer).sync,
        isDisabled: repo.disabled?(viewer: @viewer),
        isLocked: repo.locked,
        isArchived: repo.archived?,
      },
      viewer: {
        __typename: T.must(@viewer.class.name),
        id: @viewer.global_relay_id,
        login: @viewer.login # rubocop:disable GitHub/DoNotAllowLogin
      }
    }

    res.deep_stringify_keys
  end

  def get_index_variables
    {
      first: 25,
      query: "is:issue state:open repo:#{@repo_owner}/#{@repo_name} sort:created-desc",
      owner: @repo_owner,
      repo: @repo_name,
    }
  end

  def get_index_context
    {
      viewer: @viewer,
      session: {},
    }
  end

  def compare_results(control, candidate)
    control_json = JSON.pretty_generate(control)
    candidate_json = JSON.pretty_generate(candidate)
    control_json == candidate_json
  end

  # this is the baseline in prod
  def index_graphql
    response = Platform.execute(
      IndexQueryString,
      target: :internal,
      variables: get_index_variables,
      context: get_index_context,
    )

    response.data.to_h
  end

  def index_graphql_no_tracker
    context = get_index_context

    query = GraphQL::Query.new(
      Platform::Schema,
      IndexQueryString,
      context: context,
      variables: get_index_variables,
    )

    query_hash = Platform::Instrumentation::TrackingHash.generate(IndexQueryString)
    context[:query_tracker] = FakeQueryTracker.new(query, query_hash: query_hash, request_env: nil)

    response = Platform.execute(
      IndexQueryString,
      target: :internal,
      variables: get_index_variables,
      context: context,
    )

    response.data.to_h
  end

  def index_graphql_no_tracer
    res = Platform.execute(
      IndexQueryString,
      schema: CustomSchema, # using the custom schema that does not have the tracers
      target: :internal,
      variables: get_index_variables,
      context: get_index_context,
    )

    res.data.to_h
  end

  def index_graphql_no_auth
    context = get_index_context
    context[:origin] = Platform::ORIGIN_INTERNAL

    # make sure the config is the same that is being used for web unicorns where platform tracing is enabled
    OpenTelemetry::Instrumentation::GraphQL::Instrumentation.instance.config[:enable_platform_field] = true
    OpenTelemetry::Instrumentation::GraphQL::Instrumentation.instance.config[:enable_platform_authorized] = true
    OpenTelemetry::Instrumentation::GraphQL::Instrumentation.instance.config[:enable_platform_resolve_type] = true

    response = Platform.execute(
      IndexQueryString,
      target: :internal,
      variables: get_index_variables,
      context: context,
    )

    response.data.to_h
  end

  def index_graphql_no_execute
    context = get_index_context

    query = GraphQL::Query.new(
      Platform::Schema,
      IndexQueryString,
      context: context,
      variables: get_index_variables,
    )

    query_hash = Platform::Instrumentation::TrackingHash.generate(IndexQueryString)
    context[:query_tracker] = Platform::QueryTracker.new(query, query_hash: query_hash, request_env: nil)
    context[:origin] = Platform::ORIGIN_MANUAL_EXECUTION
    context[:target] = :internal

    context[:mask] = Platform::SchemaRuntimeMask.new(
      context[:target],
      environment: GitHub.runtime.current
    )
    context[:permission] = Platform::Authorization::Permission.new(context)
    context[:trace] = Platform::Schema.new_trace(
      mode: :field_tracer_mode,
      track_n_plus_one: GitHub.flipper[:gql_n_plus_one_tracer].enabled?(context[:viewer])
    )

    res = nil
    context[:query_tracker].track do
      Platform::Security::RepositoryAccess.with_viewer(context[:viewer]) do
        res = Platform::Session.run(query, context).to_h
      end
    end

    res["data"]
  end

  def index_graphql_no_auth_no_tracer_no_tracker_no_execute
    context = get_index_context
    context[:origin] = Platform::ORIGIN_INTERNAL
    query = GraphQL::Query.new(
      CustomSchema,
      IndexQueryString,
      context: context,
      variables: get_index_variables,
    )

    context[:permission] = Platform::Authorization::Permission.new(query.context)
    query_hash = Platform::Instrumentation::TrackingHash.generate(IndexQueryString)
    context[:query_tracker] = Platform::QueryTracker.new(query, query_hash: query_hash, request_env: nil)

    res = nil
    Platform::Security::RepositoryAccess.with_viewer(context[:viewer]) do
      res = Platform::Session.run(query, context).to_h
    end

    res["data"]
  end

  def track_perf(method, type)
    clear_caches
    start_allocations = GC.stat(:total_allocated_objects)
    start_query_count = GitHub::MysqlInstrumenter.query_count

    res = yield

    end_allocations = GC.stat(:total_allocated_objects)
    total_allocations = end_allocations - start_allocations

    end_query_count = GitHub::MysqlInstrumenter.query_count
    total_query_count = end_query_count - start_query_count

    GitHub.dogstats.distribution("graphql.benchmark.allocations", total_allocations, tags: ["method:#{method}", "type:#{type}"])
    GitHub.dogstats.distribution("graphql.benchmark.mysql", total_query_count, tags: ["method:#{method}", "type:#{type}"])

    res
  end

  def clear_caches
    klasses = [
      Issue,
      Repository,
      User,
      IssueComment,
      IssueEvent,
      Label,
      CrossReference,
    ]
    klasses.each { |klass| klass.connection.query_cache.clear }
  end
end
