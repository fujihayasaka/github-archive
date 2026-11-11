# typed: false
# frozen_string_literal: true

require "csv"

module OpenApi
  module CLI
    module Commands
      class AssignOperationIds < Command

        class Collector

          REPO_NAME_WITH_OWNER = %r{/repos/\{.*?\}/\{.*?\}}
          ORG_PATTERN = %r{/orgs/\{.*?\}}
          ORG_TEAM_PATTERN = %r{/orgs/\{.*?\}/teams/\{.*?\}}
          USER_PATTERN = %r{/users/\{.*?\}}
          BLACKBIRD_INTERNAL_REPO_NAME_WITH_OWNER = %r{/internal/blackbird/repos/\{.*?\}/\{.*?\}}
          MISSING_PATTERNS = [
            %r{\A/app/\{.*?\}\Z},
            %r{\A/app/installation-requests\Z},
            %r{\A/enterprise/settings/auth},
            %r{\A/languages.*},
            %r{\A/repos(itories)?/\{.*?\}/advanced-security},
            %r{\A/repos(itories)?/\{.*?\}/git/refs},
            %r{\A/repos(itories)?/\{.*?\}/git/refs/\{.*?\}},
            %r{\A/repos(itories)?/\{.*?\}/issues/\{.*?\}/assignees/\{.*?\}}
          ].freeze

          def endpoints
            @endpoints ||= find_endpoints
          end
          alias_method :run, :endpoints

          def find_endpoints
            endpoints = []
            Rails.root.glob("app/api/**/*.rb") do |file|

              lines = file.readlines
              lines.each_with_index do |line, idx|
                endpoint = Endpoint.parse(line)

                if endpoint
                  endpoints << endpoint
                  stats[:total] += 1

                  indentation = line[/\A(\s+)/, 1]

                  body_line_offset = 0
                  lines[(idx + 1)..-1].take_while { |line| !line.start_with?("#{indentation}end") }.each do |body_line|
                    if !endpoint.documentation_url && body_line =~ /@documentation_url\s*=\s*(\S+)/
                      endpoint.documentation_url = $1.strip.gsub('"', "")
                      endpoint.documentation_url_line = idx + 1 + body_line_offset
                    end

                    if !endpoint.route_owner && body_line =~ /@route_owner\s*=\s*"([^"]+?)"/
                      endpoint.route_owner = $1.strip
                      endpoint.route_owner_line = idx + 1 + body_line_offset
                    end

                    body_line_offset += 1
                  end

                  filename = file.to_s.sub(/^.*app\/api/, "app/api")
                  linenum = idx + 1

                  endpoint.source_path = filename
                  endpoint.source_line = linenum
                  endpoint.source_commit = source_commit

                  if file.to_s.include?("/internal/")
                    endpoint.disposition = :internal
                    stats[:skipped][:total] += 1
                    stats[:skipped][:internal] += 1
                    next
                  end

                  skip_path = %w[staff third-party]
                  skip_doc = %w[INTERNAL UNRELEASED DEPRECATED EXPERIMENTAL IGNORED TO_FOLLOW]

                  if endpoint.documentation_url && skip_doc.any? { |s| endpoint.documentation_url.end_with?("::#{s}") } || skip_path.any? { |s| endpoint.normalized_route.start_with?("/#{s}/") }
                    endpoint.disposition = :unsuitable
                    stats[:skipped][:total] += 1
                    stats[:skipped][:unsuitable] += 1
                    next
                  end

                  sig = [endpoint.http_method, endpoint.normalized_route]
                  operation_id = operations[sig]

                  if operation_id
                    operations.delete(sig)
                    if endpoint.operation_id
                      if operation_id != endpoint.operation_id
                        $stderr.puts "WARNING: #{filename}:#{linenum} - #{endpoint.route} (normalized to #{endpoint.normalized_route}) guessed as #{operation_id} but is currently assigned to #{endpoint.operation_id}"
                        endpoint.disposition = :reassignment
                        stats[:reassignment] += 1
                      else
                        endpoint.disposition = :noop
                        stats[:noop] += 1
                      end
                    else
                      endpoint.disposition = :assignment
                      status = "Assignment"
                      stats[:assignment] += 1
                    end
                    endpoint.operation_id = operation_id
                  elsif MISSING_PATTERNS.any? { |pattern| pattern.match(endpoint.normalized_route) }
                    if endpoint.operation_id
                      $stderr.puts "WARNING: #{filename}:#{linenum} - #{endpoint.route} (normalized to #{endpoint.normalized_route}) guessed as MISSING but is currently assigned to #{endpoint.operation_id}"
                      endpoint.disposition = :unassignment
                      stats[:unassignment] += 1
                    else
                      endpoint.disposition = :missing
                      status = "None (Missing)"
                      stats[:skipped][:total] += 1
                      stats[:skipped][:missing] += 1
                    end
                    endpoint.operation_id = nil
                  else
                    if endpoint.operation_id
                      $stderr.puts "WARNING: #{filename}:#{linenum} - #{endpoint.route} (normalized to #{endpoint.normalized_route}) guessed as UNKNOWN but is currently assigned to #{endpoint.operation_id}"
                      endpoint.disposition = :unassignment
                      stats[:unassignment] += 1
                    else
                      endpoint.disposition = :unknown
                      stats[:skipped][:total] += 1
                      stats[:skipped][:unknown] += 1
                    end
                    endpoint.operation_id = nil
                  end
                end
              end
            end
            endpoints
          end

          def source_commit
            @source_commit ||= `git rev-parse HEAD`.strip
          end

          def stats
            @stats ||= {
              total: 0,

              noop: 0,
              assignment: 0,
              reassignment: 0,
              unassignment: 0,

              skipped: {
                total: 0,

                missing: 0,
                unknown: 0,

                internal: 0,
                unsuitable: 0
               }
            }
          end

          private

          def operations
            return @operations if defined?(@operations)
            @operations = {}
            Rails.root.glob("app/api/description/operations/**/*.yaml") do |file|
              doc = YAML.load_file(file)
              http_method = doc.dig("x-github-internal", "http-method")

              path = Endpoint.normalize(doc.dig("x-github-internal", "path"))

              paths = []
              paths << path
              alternative_paths_for(path).each do |alt_path|
                paths << alt_path
              end

              paths.each do |candidate|
                @operations[[http_method, candidate]] = doc["operationId"]
              end
            end
            @operations
          end

          # This code is basically the reverse of the URL substitutions performed by GitHub::Routers::Api.
          #
          # @param path_pattern [String] an OpenAPI path pattern
          # @return [String, nil] An alias for `path_pattern`, if there's one that makes sense.
          def alternative_paths_for(path_pattern)
            alts = []

            if path_pattern.start_with?(REPO_NAME_WITH_OWNER)
              alts << path_pattern.sub(REPO_NAME_WITH_OWNER, "/repositories/{}")
            elsif path_pattern.start_with?(ORG_TEAM_PATTERN)
              alts << path_pattern.sub(ORG_TEAM_PATTERN, "/organizations/{}/team/{}")
              alts << path_pattern.sub(ORG_TEAM_PATTERN, "/orgs/{}/team/{}")
              alts << path_pattern.sub(ORG_TEAM_PATTERN, "/organizations/{}/teams/{}")
            elsif path_pattern.start_with?(ORG_PATTERN)
              alts << path_pattern.sub(ORG_PATTERN, "/organizations/{}")
            elsif path_pattern.start_with?(USER_PATTERN)
              alts << path_pattern.sub(USER_PATTERN, "/user/{}")
            elsif path_pattern.start_with?(BLACKBIRD_INTERNAL_REPO_NAME_WITH_OWNER)
              alts << path_pattern.sub(BLACKBIRD_INTERNAL_REPO_NAME_WITH_OWNER, "/internal/blackbird/repositories/{}")
            end

            alts
          end

          def first_component(path)
            path.split("/")[1]
          end
        end

        class Endpoint

          METHODS = %w[get post put patch delete]
          PATTERN = /\A\s+(#{METHODS.join("|")})\s+"([^"]+?)",?\s+(?:operation_id:\s+"([^"]*?)"\s+)?do\s*\Z/
          UPDATES = [:assignment, :reassignment, :unassignment]

          def self.parse(line)
            if line =~ PATTERN
              new($1, $2, $3)
            end
          end

          def self.normalize(path)
            path.
              gsub("*", "{}").
              gsub(/\{.*?\}/, "{}").
              gsub(/:[a-z_]+/, "{}")
          end

          attr_reader :http_method
          attr_accessor :operation_id, :route
          attr_accessor :documentation_url, :route_owner
          attr_accessor :documentation_url_line, :route_owner_line
          attr_accessor :source_path, :source_line, :source_commit
          attr_accessor :disposition

          def initialize(http_method, route, operation_id = nil)
            @http_method = http_method
            @route = route
            @operation_id = operation_id
          end

          def normalized_route
            @normalized_route ||= self.class.normalize(@route)
          end

          def source_url
            @source_url ||= "https://github.com/github/github/blob/#{source_commit}/#{source_path}#L#{source_line}"
          end

          def will_update?
            UPDATES.include?(disposition)
          end
        end

        class Reporter
          def self.run(command, collector, write: false)
            new(command, collector).run(write: write)
          end

          def initialize(command, collector)
            @command = command
            @collector = collector
          end

          def run(write:)
            @command.say "#{@collector.stats[:total]} total endpoints:", :bold
            @command.say "  - #{@collector.stats[:noop]} endpoint operation ID(s) are already assigned", :cyan
            @command.say "  - #{@collector.stats[:assignment]} endpoint operation ID(s) will be assigned", :green
            @command.say "  - #{@collector.stats[:reassignment]} endpoint operation ID(s) will be reassigned", :yellow
            @command.say "  - #{@collector.stats[:unassignment]} endpoint operation ID(s) will be unassigned", :red
            @command.say "  - #{@collector.stats[:skipped][:total]} endpoints will be skipped:"
            @command.say "    - #{@collector.stats[:skipped][:internal]} are internal endpoints"
            @command.say "    - #{@collector.stats[:skipped][:unsuitable]} are otherwise unsuitable (deprecated, experimental, marked internal, etc)"
            @command.say "    - #{@collector.stats[:skipped][:missing]} are known to be missing operation descriptions", :magenta, :bold
            @command.say "    - #{@collector.stats[:skipped][:unknown]} for otherwise unknown reasons (no operation ID matches)", :magenta

            if write
              report = build_csv do |output|
                output << [
                  "Filename",
                  "Owner",
                  "HTTP Method",
                  "Route",
                  "Operation ID",
                  "Change",
                  "Documentation URL",
                  "Source URL"
                ]
                @collector.endpoints.each do |endpoint|
                  output << [
                    endpoint.source_path,
                    endpoint.route_owner,
                    endpoint.http_method.upcase,
                    endpoint.normalized_route,
                    endpoint.operation_id,
                    [:unknown, :missing, :unsuitable].include?(endpoint.disposition) ? "Skipped:#{endpoint.disposition.capitalize}" : endpoint.disposition.capitalize,
                    endpoint.documentation_url,
                    endpoint.source_url
                  ]
                end
              end

              @command.say
              @command.say "Wrote #{Pathname.new(report.path).relative_path_from(Rails.root)} with detailed information.", :bold
            end
          end

          private

          def build_csv(&block)
            Rails.root.join("tmp", "assign-operation-ids.csv").open("w") do |file|
              yield CSV.new(file)
              file
            end
          end
        end

        class Writer
          def self.run(command, collector)
            new(command, collector).run
          end

          def initialize(command, collector)
            @command = command
            @collector = collector
          end

          def run
            Reporter.run(@command, @collector, write: false)

            @command.nl
            if @command.ask("Write changes? [y/N]", :bold).downcase == "y"
              files_to_clean = {}
              @collector.endpoints.each do |endpoint|
                if endpoint.will_update?
                  update_yaml(endpoint)
                  update_ruby(endpoint)
                  files_to_clean[endpoint.source_path] ||= []
                  files_to_clean[endpoint.source_path] << endpoint
                end
              end
              clean_files(files_to_clean)
              prettify_yaml
            else
              @command.say "No changes written.", :red
            end
          end

          def normalize_url(path)
            "${externalDocsUrl}#{path}"
          end

          def clean_files(files_to_clean)
            files_to_clean.each do |path, endpoints|
              lines = File.readlines(path)

              lines_to_remove = endpoints.flat_map do |endpoint|
                [
                  endpoint.documentation_url_line,
                  endpoint.route_owner_line
                ]
              end.compact

              if lines_to_remove.any?
                # Make sure we're removing lines from the end of the file first
                lines_to_remove.sort.reverse_each do |idx|
                  lines.delete_at(idx)
                  # Remove the next line if it's blank
                  if lines[idx].strip =~ /\A\s*\Z/
                    lines.delete_at(idx)
                  end
                end
                # Write changes
                File.open(path, "w") do |file|
                  lines.each { |line| file.puts line }
                end
              end
            end
          end

          def update_ruby(endpoint)
            source_file = Pathname.new(endpoint.source_path)
            lines = source_file.readlines
            lines[endpoint.source_line - 1] = %Q<  #{endpoint.http_method} "#{endpoint.route}", operation_id: "#{endpoint.operation_id}" do>
            File.open(endpoint.source_path, "w") do |file|
              lines.each { |line| file.puts line }
            end
          end

          def update_yaml(endpoint)
            if endpoint.operation_id
              operation_file = OpenApi.root.join("operations", endpoint.operation_id + ".yaml")
              if operation_file.exist?
                operation = YAML.safe_load(operation_file.read)
                # Set operation ID
                if endpoint.operation_id
                  operation["operationId"] = endpoint.operation_id
                else
                  operation.delete("operationId")
                end
                # Set route owner
                if endpoint.route_owner
                  operation["x-github-internal"] ||= {}
                  operation["x-github-internal"]["owner"] = endpoint.route_owner
                else
                  operation["x-github-internal"]&.delete("owner")
                end
                # Set documentation URL
                if endpoint.documentation_url
                  operation["externalDocs"] ||= { "description" => "API method documentation" }
                  operation["externalDocs"]["url"] = normalize_url(endpoint.documentation_url)
                else
                  operation.delete("externalDocs")
                end
                # Write
                operation_file.open("w") do |file|
                  file.write(YAML.dump(operation))
                end
              else
                @command.say "No operation file found for operation_id #{endpoint.operation_id}", :red, :bold
              end
            end
          end

          def prettify_yaml
            @command.say "Prettifying YAML files...", :yellow, :bold
            system("bin/prettier", "--loglevel", "warn", "--write", OpenApi.root.join("operations").to_s)
          end
        end

        def run(dry_run:)
          collector = Collector.new
          collector.run
          if dry_run
            Reporter.run(self, collector, write: true)
          else
            Writer.run(self, collector)
          end
        end
      end
    end
  end
end
