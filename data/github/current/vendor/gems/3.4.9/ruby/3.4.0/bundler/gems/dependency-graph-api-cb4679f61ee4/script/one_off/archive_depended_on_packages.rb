#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Generates json of all dependend on packages (>1 dependent) and their dependent counts
# Usage: script/one_off/archive_depended_on_packages.rb (-s, --save)
#
# Output:
# List of depended on packages including:
#   Ecosystem
#   Package name
#   Dependents Count
#   Repository NWO


require_relative "../../config/environment"
require "json"
require "optparse"

@options = { save: false }

OptionParser.new do |opts|
  opts.on("-s", "--save", "Run through input file and save output") do |flag|
    @options[:save] = true
  end
end.parse!(Array(ARGV))

@checkpoint = Checkpoint.find_or_create_by(name: "archive_dependents")

def run_export
  puts "Starting export.."

  output_path = Rails.root.join("script/one_off/depended_on_packages.json")
  File.delete(output_path) if File.exist?(output_path) if @options[:save]
  puts "using #{output_path} for output"

  ActiveRecord::Base.connected_to(role: :analytics) do
    join = Views::AbstractRepositoryDependencyCount.joins("INNER JOIN #{Package.table_name}
      ON #{Package.table_name}.package_manager = #{Views::AbstractRepositoryDependencyCount.table_name}.package_manager
      AND #{Package.table_name}.name = #{Views::AbstractRepositoryDependencyCount.table_name}.package_name",
      "INNER JOIN #{Repository.table_name} ON #{Repository.table_name}.github_repository_id = #{Package.table_name}.repository_id")
      .select("#{Views::AbstractRepositoryDependencyCount.table_name}.*, #{Package.table_name}.repository_nwo as repo_nwo")

      File.open(output_path, "a") { |f| f.puts("[") }

    join.in_batches do |batch|
        dependencies = batch.as_json.select { |dependency| dependency["dependent_count"] > 0 }

        if @options[:save]
          File.open(output_path, "a") { |f| dependencies.each { |dependency| f.puts("#{JSON.dump(dependency)},") } }
          puts "packages from #{batch.first.id} to #{batch.last.id} were written to output file"
          ActiveRecord::Base.connected_to(role: :writing) do
            @checkpoint.update(last_checkpointed_id: batch.first.id)
          end
        else
          puts dependencies
        end
    end

    File.open(output_path, "r+") do |f|
      lines = f.each_line.to_a
      lines.last.strip!.delete_suffix!(",") # remove the last comma for valid JSON

      f.rewind
      f.puts(lines.join)
      f.puts("]")
    end
  end
  puts "All done!"
end

run_export
