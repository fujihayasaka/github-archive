# typed: strict
# frozen_string_literal: true

# Report Sorbet coverage. See script/report_code_stats.rb for more info

require "code_stats"
require "spoom"
require "gh/dev/sorbet/file_sigils"
require "gh/dev/code_stats/base"

module GH
  module Dev
    class CodeStats
      class Sorbet < Base
        extend T::Helpers

        sig { override.void }
        def report_data!
          GH::Dev::Sorbet::FileSigils.new.service_counts(serviceowners).each do |service, types|
            types.each do |type, sigils|
              sigils.each do |sigil, count|
                tags = [
                  "repo:github/github",
                  "sigil:#{sigil}",
                  "file_type:#{type}",
                ]

                tags << "catalog_service:github/#{service}" if service

                report.gauge("sorbet.files", count, tags)
              end
            end
          end

          context = Spoom::Context.new(Dir.pwd)
          snapshot = Spoom::Coverage.snapshot(context, rbi: false)

          report.gauge("sorbet.methods", snapshot.methods_with_sig, ["typed:true", "repo:github/github"])
          report.gauge("sorbet.methods", snapshot.methods_without_sig, ["typed:false", "repo:github/github"])
          report.gauge("sorbet.calls", snapshot.calls_typed, ["typed:true", "repo:github/github"])
          report.gauge("sorbet.calls", snapshot.calls_untyped, ["typed:false", "repo:github/github"])

          todo_line_count = 0
          if File.exist?("sorbet/rbi/todo.rbi")
            todo_line_count = File.readlines("sorbet/rbi/todo.rbi").count do |line|
              !line.start_with?("#") && !line.strip.empty?
            end
          end

          report.gauge("sorbet.todo", todo_line_count, ["repo:github/github"])
        end
      end
    end
  end
end
