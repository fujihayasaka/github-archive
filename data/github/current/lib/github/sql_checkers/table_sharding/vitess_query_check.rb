# typed: true
# frozen_string_literal: true

require_relative "../../vivid_cortex_api"
require "octokit"
require "open3"

# invoked through script/vitess_query_checker.rb

# This class is intended as an analysis tool to verify queries from a standard mysql cluster will
# run successfully against a sharded vitess cluster. Prior data-partitioning efforts used this tool
# to look for problematic queries prior to actually sending traffic to a vitess cluster.

# It uses the vividcortex api to pull a list of queries from production traffic.
# Those queries are then sent to `vtexplain` to determine whether vitess can parse this query,
# and what actions vitess will take with that query input.
# The output is captured in files under the OUTPUT_DIR directory.
class GitHub::SQLCheckers::TableSharding::VitessQueryCheck
  OUTPUT_DIR = "/workspaces/data-partitioning/vividcortex_analysis"
  ISSUES_REPO = "github/data-partitioning"
  SLEEP_SECONDS = 10

  CMDS = {
    ApplicationRecord::RepositoriesActionsChecks =>  {
      prepare: 'echo "{ \"github_test_vt\": $(cat db/vschema/github_test_vt/vschema.json), \"github_test_repositories_actions_checks\": $(cat db/vschema/github_test_repositories_actions_checks/vschema.json) }" > %{output_dir}/repo-actions-vschema.json && '\
        '"$(cat db/repositories-actions-checks-structure.sql)" > %{output_dir}/repo-actions-structure.sql' % { output_dir: OUTPUT_DIR },
      explain: "vtexplain --shards 2 --vschema-file %{output_dir}/repo-actions-vschema.json --schema-file %{output_dir}/repo-actions-structure.sql --output-mode json --sql-file %{output_dir}/query.sql > %{output_dir}/dump.txt" % { output_dir: OUTPUT_DIR }
    },
    ApplicationRecord::IssuesPullRequests => {
      prepare: 'echo "{ \"github_test_vt\": $(cat db/vschema/github_test_vt/vschema.json), \"github_test_issues_pull_requests\": $(cat db/vschema/github_test_issues_pull_requests/vschema.json) }" > %{output_dir}/issues-prs-vschema-temp.json && '\
        'echo "$(cat db/issues-pull-requests-structure.sql)" > %{output_dir}/issues-prs-schema-temp.sql' % { output_dir: OUTPUT_DIR },
      explain: "vtexplain --planner-version gen4 --shards 2 --vschema-file %{output_dir}/issues-prs-vschema-temp.json --schema-file %{output_dir}/issues-prs-schema-temp.sql --output-mode json --sql-file %{output_dir}/query.sql > %{output_dir}/dump.txt" % { output_dir: OUTPUT_DIR }
    }
  }

  VALID_QUERY_TYPES = %w[select insert update delete]
  FILTERS = { "update" => "^update*`", "select" => "^select*`", "delete" => "^delete*`" }

  def self.display_queries(queried_tables, domain_class, query_type)
    dry_run = !(ENV["WRITE"] == "1")
    hosts = GitHub::VividCortexApi.fetch_hosts_for_domain(domain_class)
    @issues_opened = 0
    @issues_updated = 0
    @issues_reopened = 0
    @issues_closed = 0
    @issue_errors = Hash.new { |h, k| h[k] = [] }

    client = Octokit::Client.new(access_token: ENV["PAT"], per_page: 100)
    client.auto_paginate = true
    table_errors = []
    `mkdir -p #{OUTPUT_DIR}`
    system(CMDS[domain_class][:prepare])

    queried_tables.each do |table|
      queries = self.new(table, domain_class, query_type, hosts, client, dry_run).display_queries
    rescue => err # rubocop:todo Lint/RescueException
      table_errors << table
      puts "Error fetching queries for #{table}: #{err}"
    end

    puts "***Complete***"
    puts "VividCortex API failed to fetch queries for #{table_errors.join(", ")}" if table_errors.length > 0
    puts "#{@issues_opened} New Issues Created"
    puts "#{@issues_updated} Existing Issues Updated"
    puts "#{@issues_reopened} Existing Issues Reopened"
    puts "#{@issues_closed} Existing Issues Closed"

    if !@issue_errors.empty?
      puts "Errors creating issues through GitHub API for the following tables: #{@issue_errors.keys.join(", ")}"
      @issue_errors.map do |table, errors|
        error_messages = errors.map { |e| "#{e.response_status}: #{e.response_body}: #{e.errors}" }.join(", ")
        puts "Errors for #{table}: #{error_messages}"
      end
    end
  end

  def self.issues
    return @issues if defined?(@issues)

    client = Octokit::Client.new(access_token: ENV["PAT"])
    client.auto_paginate = true

    @issues = client
      .search_issues("is:issue repo:#{ISSUES_REPO} label:problematic-queries").items
      .group_by { |i| i.title.slice(/\A\S+/) }
      .transform_values { |issues| issues[0] }

    @issues
  end

  def self.add_issue(id, issue)
    @issues[id] = issue
    @issues_opened += 1
  end

  def self.increment_issues_updated
    @issues_updated += 1
  end

  def self.increment_issues_reopened
    @issues_reopened += 1
  end

  def self.increment_issues_closed
    @issues_closed += 1
  end

  def self.log_issue_error(table, err)
    @issue_errors[table] << err
  end

  attr_reader :table, :domain_class, :query_type, :filter_root, :hosts, :query_strings, :lost_queries, :lost_samples, :simple_queries,
    :problem_queries, :explain_errors, :deconstructed_queries, :dry_run, :client

  def initialize(table, domain_class, query_type, hosts, client, dry_run = false)
    @table = table
    @domain_class = domain_class
    raise ArgumentError unless VALID_QUERY_TYPES.include?(query_type)
    @query_type = query_type
    @filter_root = FILTERS[query_type]
    @hosts = hosts
    @client = client
    @dry_run = dry_run
    @query_strings = {}
    @lost_queries = {}
    @lost_samples = []
    @simple_queries, @problem_queries, @explain_errors, @deconstructed_queries = 0, 0, 0, 0
  end

  def display_queries
    `mkdir -p #{table_query_path}`
    find_query_strings
    explain_queries
    catalog_lost_queries
    catalog_summary
  end

  private

  def find_query_strings
    queries.each do |k, v|
      valid_sample_found = T.let(false, T::Boolean)
      last_sample = T.let(nil, T.untyped)
      samples = GitHub::VividCortexApi.fetch_samples(k)
      samples.each do |s|
        last_sample = s
        next if s["truncated"]
        query_strings[k] = Base64.decode64(s["text"])
        valid_sample_found = true
        break
      end
      lost_queries[k] = v if !valid_sample_found
      lost_samples << last_sample if !valid_sample_found && !last_sample.nil?
    end
  end

  def explain_queries
    File.open(table_query_path("/problematic_queries.md"), "w")
    File.open(table_query_path("/deconstructed_queries.md"), "w")
    File.open(table_query_path("/explain_errors.md"), "w")
    query_strings.each do |k, v|
      begin
        File.open("#{OUTPUT_DIR}/query.sql", "wb") { |file| file.write(v) }
        result = system(CMDS[domain_class][:explain])
        content = File.read("#{OUTPUT_DIR}/dump.txt")
        plans = JSON.parse(content)[0]["Plans"]
        if simple_query?(plans)
          @simple_queries += 1
          close_issue(k)
          next
        end


        body = explain_markdown(k, v, plans, content)
        if problem_categories(plans).include?("deconstructed")
          @deconstructed_queries += 1
          File.open(table_query_path("/deconstructed_queries.md"), "a") do |f|
            f.puts body
          end
        else
          @problem_queries += 1
          File.open(table_query_path("/problematic_queries.md"), "a") do |f|
            f.puts body
          end
        end
        create_or_update_issue(k, body, plans)
      rescue JSON::ParserError => err
        @explain_errors += 1
        body = explain_error_body_markdown(k, v, content)
        File.open(table_query_path("/explain_errors.md"), "a") do |f|
          f.puts body
        end
        create_or_update_issue(k, body, plans || [])
      end
    end
  end

  def catalog_lost_queries
    body = lost_queries.map do |id, query|
      lost_query_body_markdown(id, query)
    end.join("<br><br>") + "<br><br>"

    body += lost_samples.map do |sample|
      "lost query sample: #{Base64.decode64(sample["text"])}<br><br>"
    end.join

    body += "<br>Generated using Vitess #{vtcombo_version}"

    File.open(table_query_path("lost_queries.md"), "w") { |f| f.puts body }

    id = "#{table}-#{query_type}-lost-queries"
    if lost_queries.length + lost_samples.length == 0
      close_issue(id)
    else
      create_or_update_issue(id, body)
    end
  end

  def catalog_summary
    File.open(table_query_path("README.md"), "w") do |f|
      f.puts "Fetched #{queries.length} queries<br>"
      f.puts "Identified #{problem_queries} problematic queries<br>"
      f.puts "Identified #{deconstructed_queries} deconstructed queries<br>"
      f.puts "Lost #{lost_queries.length} queries<br>"
      f.puts "Errored #{explain_errors} times during explain<br>"
      f.puts "Accepted #{simple_queries} as simple queries<br>"
      f.puts "#{100 - (((problem_queries + deconstructed_queries + lost_queries.length + explain_errors) / [queries.length.to_f, 1].max) * 100).round}% of queries were accepted<br>"
      f.puts "Run using a window of #{GitHub::VividCortexApi.range_in_seconds} seconds in VividCortex API"
    end
  end

  def table_query_path(filepath = "")
    File.join("#{OUTPUT_DIR}/#{table}/#{query_type}/", filepath)
  end

  def queries
    @queries ||= GitHub::VividCortexApi.fetch_queries(filter_root, table, hosts)
  end

  def simple_query?(query_plans)
    # it is a simple query if each Vitess query is a simple one
    simple = T.let(true, T::Boolean)
    return simple if query_plans.nil?
    query_plans.each do |plan|
      next if simple_plan?(plan["Instructions"])
      simple = false
    end
    simple
  end

  def simple_plan?(plan)
    return true if plan["OperatorType"] == "Route" && %w[IN EqualUnique None ByDestination].include?(plan["Variant"])
    return true if %w[Update Delete].include?(plan["OperatorType"]) && %w[Equal EqualUnique In].include?(plan["Variant"])
    return false unless %w[Aggregate Limit VindexLookup].include?(plan["OperatorType"])
    return false if plan["Inputs"].length > 2

    if plan["OperatorType"] == "VindexLookup" && plan["Inputs"].length == 2
      # if there are multiple queries, one should be a vindex lookup, the other the original mysql query
      return false unless plan["Inputs"].any? { |input| vindex_lookup?(input) }
    end

    plan["Inputs"].each do |input|
      return false unless simple_plan?(input)
    end
    true
  end

  def vindex_lookup?(input)
    input.key?("Vindex") && input["Table"]&.ends_with?("_idx")
  end

  def problem_categories(plans)
    return [@query_type] unless @query_type == "select"
    cats = []
    plans.each do |p|
      cats.concat(problem_category(p["Instructions"]))
    end
    cats.sort.uniq.map(&:downcase)
  end

  def problem_category(plan)
    cat = T.let([], T::Array[String])
    cat << plan["OperatorType"] unless %w[Route Aggregate Limit VindexLookup].include?(plan["OperatorType"])
    if plan["OperatorType"] == "Route"
      cat << plan["Variant"] unless %w[EqualUnique None IN].include?(plan["Variant"])
    end
    return cat if plan["Inputs"].nil?

    if plan["Inputs"].length >= 2 && plan["Inputs"].none? { |input| vindex_lookup?(input) }
      cat << "deconstructed"
    end

    plan["Inputs"].each do |input|
      cat = cat.concat(problem_category(input))
    end
    cat
  end

  def format_query(query)
    q = query.dup
    i1 = query.index("FROM")
    q = q.insert(i1, "\n") unless i1.nil?
    i2 = q.index("WHERE")
    q = q.insert(i2, "\n") unless i2.nil?
    i3 = q.index("GROUP")
    q = q.insert(i3, "\n") unless i3.nil?
    i4 = q.index("ORDER")
    q = q.insert(i4, "\n") unless i4.nil?
    q
  end

  def explain_markdown(id, query, plans, explain_output)
    "Problematic query #{id} for Vitess:
Categories: #{problem_categories(plans).join(', ')}

```sql
#{format_query(query)}
```

vtexplain output:

```json
#{explain_output}
```

VividCortex [link](#{vivid_cortex_link(id)})

Generated using Vitess #{vtcombo_version}
"
  end

  def lost_query_body_markdown(id, query)
    "Lost query #{id} for Vitess:

```sql
#{format_query(query)}
```

VividCortex [link](#{vivid_cortex_link(id)})

"
  end

  def explain_error_body_markdown(id, query, content)
    "Explain error for query #{id} for Vitess:

Vitess errored during explain. Original query:

```sql
#{format_query(query)}
```

Content:
#{content}

VividCortex [link](#{vivid_cortex_link(id)})

Generated using Vitess #{vtcombo_version}"
  end

  def create_or_update_issue(id, body, plans = [])
    return if dry_run

    labels = ["problematic-queries"] + problem_categories(plans)
    existing_issue = GitHub::SQLCheckers::TableSharding::VitessQueryCheck.issues[id]
    title = "#{id} #{query_type.titlecase} #{table} #{problem_categories(plans).join(", ")}"

    if existing_issue
      return if existing_issue.state == "closed" && existing_issue.state_reason == "not_planned"

      client.update_issue(ISSUES_REPO, existing_issue.number, title, body, state: "open", labels: labels)

      if existing_issue.state == "closed"
        GitHub::SQLCheckers::TableSharding::VitessQueryCheck.increment_issues_reopened
      else
        GitHub::SQLCheckers::TableSharding::VitessQueryCheck.increment_issues_updated
      end
    else
      new_issue = client.create_issue(ISSUES_REPO, title, body, labels: labels)
      GitHub::SQLCheckers::TableSharding::VitessQueryCheck.add_issue(id, new_issue)
      new_issue
    end
    sleep SLEEP_SECONDS
    rescue Octokit::Error => err
      GitHub::SQLCheckers::TableSharding::VitessQueryCheck.log_issue_error(table, err)
  end

  def close_issue(id)
    return if dry_run

    existing_issue = GitHub::SQLCheckers::TableSharding::VitessQueryCheck.issues[id]
    return unless existing_issue

    body = "Vitess now shows no problems. Closing.<br><br>Fixed by Vitess: #{vtcombo_version}<br><br>"
    body += existing_issue.body

    client.update_issue(ISSUES_REPO, existing_issue.number, existing_issue.title, body, state: "closed")
    GitHub::SQLCheckers::TableSharding::VitessQueryCheck.increment_issues_closed
    sleep SLEEP_SECONDS
    rescue Octokit::Error => err
      GitHub::SQLCheckers::TableSharding::VitessQueryCheck.log_issue_error(table, err)
  end

  def vtcombo_version
    @vtcombo_version ||= Open3.capture3("vtcombo --version").first
  end

  def vivid_cortex_link(id)
    "https://githubinc.app.vividcortex.com/Default/queries/#{id}?hosts=#{hosts.join(",")}&from=-3600&until=0&selectedGraph=Average%20Latency&explainTab=Table&showSamples&showSampleFilter=false&markersEnabled"
  end
end
