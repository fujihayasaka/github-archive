#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# generate-routing-schema.rb
#
# This script is the entrypoint for generating routing details for consumption by the API Gateway agent.
#
# See these other resources for more context on the Sinatra route resolution related to the REST API:
#
#  - lib/github/routers/api.rb - this converts requests to the internal representation (if needed) and resolves the
#                                API handler to process each request
#  - lib/open_api/router.rb - this file handles some OpenAPI validation of routes and converting to internal
#                             representations
#

require "open3"
require "optparse"
require "sorbet-runtime"
require "yaml"

# Source: https://github.com/samuelgiles/sorbet-struct-comparable
#
# Imported directly as this is not available in the monolith and will never be supported by Sorbet due to
# compatibility reasons with existing code that relies on reference equality.
module T
  class Struct
    module ActsAsComparable
      extend T::Sig  # rubocop:todo Sorbet/RedundantExtendTSig

      include ::Comparable

      EQUAL = 0
      NOT_COMPARABLE = nil

      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        return NOT_COMPARABLE if other.class != T.unsafe(self).class

        T.unsafe(self).class.decorator.props.keys.each do |attribute_key|
          compare_result = T.unsafe(self).send(attribute_key) <=> other.send(attribute_key) # rubocop:todo GitHub/AvoidObjectSendWithDynamicMethod
          return T.cast(compare_result, T.nilable(Integer)) if compare_result != EQUAL
        end

        EQUAL
      end

      sig { params(other: Object).returns(T::Boolean) }
      def eql?(other)
        self == other
      end

      sig { returns(Integer) }
      def hash
        T.unsafe(self).class.decorator.props.keys.map { |attribute_key| T.unsafe(self).send(attribute_key).hash }.hash # rubocop:todo GitHub/AvoidObjectSendWithDynamicMethod
      end
    end
  end
end

class RouteMetadata < T::Struct
  include T::Struct::ActsAsComparable

  const :operation_ids, String
  const :http_method, String
  const :catalog_service, String
  const :allow_unauthenticated_access, T::Boolean
end

class RouteDefinition < T::Struct
  const :route, String
  const :metadata, T::Array[RouteMetadata]
end

class RouteChange < T::Struct
  const :route, String
  const :http_method, String
  const :changes, T::Hash[String, T.untyped] # hash of changes, e.g. {http_method: [old_value, new_value], catalog_service: [old_value, new_value]}
end

# RouteGenerator handles the reusable logic for generating route details to compose the end schema
class RouteParser
  extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

  include Kernel

  attr_reader :routes

  sig { params(routes: T::Array[RouteDefinition]).void }
  def initialize(routes)
    @routes = routes
  end

  def self.load(config)
    obj = YAML.safe_load(config)

    routes = T.let([], T::Array[RouteDefinition])

    obj.each do |key, value|
      metadata = T.let([], T::Array[RouteMetadata])

      value.each do |entry|
        metadata << RouteMetadata.new(
          operation_ids: entry["operation_ids"],
          http_method: entry["method"],
          catalog_service: entry["catalog_service"],
          allow_unauthenticated_access: entry["allow_unauthenticated_access"],
        )
      end

      routes << RouteDefinition.new(
        route: key,
        metadata: metadata,
      )
    end

    RouteParser.new(routes)
  end
end

class RouteComparer
  extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

  include Kernel

  attr_reader :base_routes, :head_routes

  sig { params(base_routes: T::Array[RouteDefinition], head_routes: T::Array[RouteDefinition]).void }
  def initialize(base_routes, head_routes)
    @base_routes = base_routes
    @head_routes = head_routes
  end

  def changes?
    return true if additions.any?
    return true if deletions.any?
    return true if modifications.any?

    false
  end

  sig { returns(Integer) }
  def base_handler_count
    return @base_handler_count if defined?(@base_handler_count)

    @base_handler_count = @base_routes.map { |route| route.metadata.size }.sum

    @base_handler_count
  end

  sig { returns(Integer) }
  def head_handler_count
    return @head_handler_count if defined?(@head_handler_count)

    @head_handler_count = @head_routes.map { |route| route.metadata.size }.sum

    @head_handler_count
  end

  sig { returns(T::Array[RouteDefinition]) }
  def additions
    return @added_routes if defined?(@added_routes)

    existing_routes = @head_routes.filter do |h|
      @base_routes.find { |r| r.route == h.route }
    end

    @added_routes = @head_routes - existing_routes

    # find new top-level routes
    existing_routes = @head_routes.filter do |h|
      @base_routes.find { |r| r.route == h.route }
    end

    # find new verbs within existing routes
    existing_routes.each do |route|
      base_route = @base_routes.find { |r| r.route == route.route }
      next unless base_route

      route.metadata.each do |metadata|
        base_metadata = base_route.metadata.find { |m| m.http_method == metadata.http_method }

        if base_metadata.nil?
          @added_routes << RouteDefinition.new(
           route: route.route,
           metadata: [metadata],
         )
        end
      end
    end

    @added_routes
  end

  sig { returns(T::Array[RouteDefinition]) }
  def deletions
    return @deleted_routes if defined?(@deleted_routes)

    existing_routes = @base_routes.filter do |h|
      @head_routes.find { |r| r.route == h.route }
    end

    @deleted_routes = @base_routes - existing_routes

    # find verbs within base route that are no longer in the head route
    @base_routes.each do |base_route|
      head_route = @head_routes.find { |r| r.route == base_route.route }
      next unless head_route

      base_route.metadata.each do |metadata|
        head_metadata = head_route.metadata.find { |m| m.http_method == metadata.http_method }

        if head_metadata.nil?
          @deleted_routes << RouteDefinition.new(
           route: base_route.route,
           metadata: [metadata],
         )
        end
      end
    end

    @deleted_routes
  end

  sig { returns(T::Array[RouteChange]) }
  def modifications
    return @modified_routes if defined?(@modified_routes)

    existing_routes = @head_routes.filter do |h|
      @base_routes.find { |r| r.route == h.route }
    end

    modifications = T.let([], T::Array[RouteChange])

    existing_routes.each do |route|
      base_route = @base_routes.find { |r| r.route == route.route }
      next unless base_route

      route.metadata.each do |metadata|
        base_metadata = base_route.metadata.find { |m| m.http_method == metadata.http_method }

        # if the base metadata is present and it's different, summarize the changes in a hash
        if !base_metadata.nil? && metadata != base_metadata
          # returns the diff in a hash #=>{key: [obj1.value, obj2.value]}
          changes = base_metadata.serialize.each_with_object({}) do |(key, _value), diff|
            if base_metadata.send(key) != metadata.send(key) # rubocop:todo GitHub/AvoidObjectSendWithDynamicMethod
              diff[key] = [base_metadata.send(key), metadata.send(key)]  # rubocop:todo GitHub/AvoidObjectSendWithDynamicMethod
            end
          end

          modifications << RouteChange.new(
            route: route.route,
            http_method: metadata.http_method,
            changes: changes,
          )
        end
      end
    end

    @modified_routes = modifications

    @modified_routes
  end
end

class DiagnosticRouteReport
  extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

  sig { params(comparer: RouteComparer).void }
  def self.render(comparer)
    puts "Outputting review summary to stdout"

    puts "Base branch has #{comparer.base_routes.size} routes and #{comparer.base_handler_count} handlers"
    puts "Head branch has #{comparer.head_routes.size} routes and #{comparer.head_handler_count} handlers"

    if comparer.changes?
      puts "Changes detected for routes on branch compared to base branch..."

      if comparer.additions.any?
        puts "Routes added:"
        comparer.additions.each do |route|
          route.metadata.each do |metadata|
            puts " - '#{metadata.http_method} #{route.route}' [catalog service: #{metadata.catalog_service}]"
          end
        end
        puts
      end

      if comparer.deletions.any?
        puts "Routes removed:"
        comparer.deletions.each do |route|
          route.metadata.each do |metadata|
            puts " - '#{metadata.http_method} #{route.route}' [catalog service: #{metadata.catalog_service}]"
          end
        end
        puts
      end

      if comparer.modifications.any?
        puts "Routes modified:"
        comparer.modifications.each do |modification|
          puts " - '#{modification.http_method} #{modification.route}'"
          changes = modification.changes.map do |key, values|
            puts "     - #{key}: '#{values[0]}' -> '#{values[1]}'"  # rubocop:todo GitHub/AvoidObjectSendWithDynamicMethod
          end.join(", ")
        end
        puts
      end
    else
      puts "No changes detected in routing schema"
    end
  end
end

class MarkdownRouteReport
  extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

  NEW_ROUTES_SECTION = <<~EOS
## New routes

These new routes have been added to the current configuration file:

{{items}}

Without synchronizing these new routes to the Gateway routing agent, new requests will not be routed correctly when the Gateway starts processing requests later this year.

EOS

  REMOVED_ROUTES_SECTION = <<~EOS
## Removed routes

These routes have been removed from the current configuration file:

{{items}}

Synchronizing these changes to the Gateway routing agent will ensure that requests to these endpoints are rejected when the monolith has removed this functionality.

EOS

  MODIFIED_ROUTES_SECTION = <<~EOS
## Modified routes

These routes have changed compared to the base configuration file:

{{items}}

Please review these changes, and update `config/access_control/programmatic_access.yaml` if these values are incorrect.

EOS

  UNTRACKED_CHANGES_TEMPLATE = <<~EOS
> [!WARNING]
> These changes are not yet committed to this branch, so what you see in this report is out of sync with what is currently on the branch.
>
> Please run this command in your codespace to observe these changes:
>
> ```
> bundle exec script/generate-routing-schema.rb
> git diff
> ```
>
> If these changes are fine to include in the API Gateway, please run this command in your codespace to include in this pull request:
>
> ```
> git commit -am "added new changes to API Gateway routing configuration"
> git push
> ```
EOS


  AUTOMATED_REVIEW_TEMPLATE = <<~EOS
# API Gateway automated review

We have detected changes to routes that should be propagated to the API Gateway routing agent so that the API Gateway will be able to successfully direct requests to these routes to the `github/github` backend.

> [!NOTE]
> The API Gateway is under active development, but is not handling production traffic yet. Please reach out to [#api-gateway-vteam](https://github-grid.enterprise.slack.com/archives/C0815QNLSP9) in Slack if you have any questions about the information below.

{{added-routes-section}}

{{removed-routes-section}}

{{modified-routes-section}}

{{untracked-changes-section}}

## Troubleshooting

<details>

<summary>To run this script in your codespace:</summary>

```
> git fetch origin {{base-sha}}
> bundle exec script/generate-routing-schema.rb
> bundle exec script/review-routing-schema-changes.rb --base {{base-sha}} {{head-args}}
```

</details>
EOS

  sig { params(routes: T::Array[RouteDefinition], section_template: String).returns(String) }
  def self.render_list(routes, section_template)
    return "" if routes.empty?

    items = routes.map do |route|
      route.metadata.map do |metadata|
        "- `#{metadata.http_method} #{route.route}`"
      end.join("\n")
    end.join("\n")

    section_template.gsub("{{items}}", items)
  end

  sig { params(routes: T::Array[RouteChange], section_template: String).returns(String) }
  def self.render_modifications(routes, section_template)
    return "" if routes.empty?

    items = routes.map do |route|
      changes = route.changes.map do |key, values|
        "     - `#{key}`: '#{values[0]}' -> '#{values[1]}'"  # rubocop:todo GitHub/AvoidObjectSendWithDynamicMethod
      end.join("\n")
      "- `#{route.http_method} #{route.route}` \n#{changes}"

    end.join("\n")

    section_template.gsub("{{items}}", items)
  end


  sig { params(comparer: RouteComparer, options: T::Hash[Symbol, T.untyped]).void }
  def self.render(comparer, options)
    return unless comparer.changes?
    return if options[:output].nil?

    expanded_file_path = T.cast(options[:output], String)

    puts "Writing report to #{expanded_file_path}"

    File.delete(expanded_file_path) if File.exist?(expanded_file_path)

    writable_file = File.open(expanded_file_path, "w")

    additions_section = render_list(comparer.additions, NEW_ROUTES_SECTION)
    removals_section = render_list(comparer.deletions, REMOVED_ROUTES_SECTION)
    modified_section = render_modifications(comparer.modifications, MODIFIED_ROUTES_SECTION)

    warning_section = if options[:untracked]
      UNTRACKED_CHANGES_TEMPLATE
    else
      ""
    end

    head_args = if options[:untracked]
      "--untracked"
    else
      "--head #{options[:head]}"
    end

    markdown_comment = AUTOMATED_REVIEW_TEMPLATE
      .gsub("{{added-routes-section}}", additions_section)
      .gsub("{{removed-routes-section}}", removals_section)
      .gsub("{{modified-routes-section}}", modified_section)
      .gsub("{{untracked-changes-section}}", warning_section)
      .gsub("{{base-sha}}", options[:base])
      .gsub("{{head-args}}", head_args)

    writable_file.puts markdown_comment
  end
end

def safe_system(command)
  stdout_str, error_str, status = Open3.capture3(command)
  if status.success?
    stdout_str
  else
    puts "stderr: #{error_str}"
    puts "stdout: #{stdout_str}"
    raise "'#{command}' failed with status #{status}"
  end
end

options = {}
OptionParser.new do |opt|
  opt.on("--base [commit-id]") { |o| options[:base] = o }
  opt.on("--head [commit-id]") { |o| options[:head] = o }
  opt.on("--untracked") { |_o| options[:untracked] = true }
  opt.on("--output [path]") { |o| options[:output] = o }
end.parse!

root_directory = File.expand_path("..", __dir__)
config_file = "app/api/gateway-routes.yaml"
output_file = File.join(root_directory, config_file)

if options[:base].nil?
  options[:base] = safe_system("git rev-parse master").strip
end

if options[:untracked]
  puts "Comparing route schema changes between '#{options[:base]}' and local working directory"
  head_config = File.read(config_file)
elsif options[:head].nil?
  options[:head] = safe_system("git rev-parse HEAD").strip
  puts "Comparing route schema changes between '#{options[:base]}' and '#{options[:head]}'"
  head_config = safe_system("git cat-file blob #{options[:head]}:#{config_file}")
else
  puts "Comparing route schema changes between '#{options[:base]}' and '#{options[:head]}'"
  head_config = safe_system("git cat-file blob #{options[:head]}:#{config_file}")
end

base_config = safe_system("git cat-file blob #{options[:base]}:#{config_file}")
base_routes = RouteParser.load(base_config)
head_routes = RouteParser.load(head_config)

comparer = RouteComparer.new(base_routes.routes, head_routes.routes)

if options[:output].nil?
  DiagnosticRouteReport.render(comparer)
else
  MarkdownRouteReport.render(comparer, options)
end
