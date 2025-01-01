#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Pull dependencies and transitive dependencies for specific repositories
# Usage: script/one_off/alt_archive_data_export.rb
#
# Output:
# List of dependencies for each repository including:
#   Ecosystem
#   Package name
#   Package version
#   Source repository for package


require_relative "../../../config/environment"
require "json"
require "optparse"

TIMEOUT = 30.minutes

@options = { mode: :run, save: false, depth: 50, repo: nil, timeout: TIMEOUT, dir: :nil }

OptionParser.new do |opts|

  opts.on("-s", "--save", "Run through input repo and save output") do |flag|
    @options[:save] = true
  end

  opts.on("-r=REPO", "--repo=REPO", "Generate graph for specific repo") do |repo|
    raise "Need to provide a repo" if repo.nil?
    @options[:repo] = repo
  end

  opts.on("-d=DEPTH", "--depth=DEPTH", "Set # levels to graph") do |depth|
    @options[:depth] = depth.to_i
  end

  opts.on("-x=NUM", "--timeout=NUM", "Set # of minutes before timing out") do |num|
    @options[:timeout] = num.to_i.minutes
  end

  opts.on("-c=DIR", "--clean=DIR", "Set mode to clean and then clean out given directory") do |dir|
    @options[:mode] = :clean
    @options[:dir] = dir
  end
end.parse!(Array(ARGV))

@checkpoint = Checkpoint.find_or_create_by(name: "last_repo_archive_graph_export")

@already_fetched_dependencies = []
@full_graph = []

def generate_graph(repo_nwo)
  ActiveRecord::Base.connected_to(role: :analytics) do
    repo = Repository.where(nwo: repo_nwo).first
    if repo.nil?
      log_repo(:missing, repo_nwo)
      exit
    end

    start = Time.now

    manifests = Manifest.where(repository_id: repo.id).pluck(:id)

    if manifests.nil?
      log_repo(:missing, repo_nwo)
      exit
    end


    output_path = Rails.root.join("script/one_off/archive_export/#{repo_nwo.gsub("/", "~")}.json")

    selection = []
    manifests.in_groups_of(10, false) do |ids|
      selection.concat(ManifestDependency.where(manifest_id: ids).select(:package_name, :package_manager))
    end

    selection = selection.uniq
    if selection.empty?
      log_repo(:empty, repo_nwo)
      exit
    end

    selection.each do |md|
      output = fetch_dependencies(repo_nwo, package_name: md.package_name, package_manager: md.package_manager, depth: @options[:depth] - 1, start: start)&.first

      if @options[:save]
        puts "adding #{md.package_manager.human_name} #{md.package_name} to graph"
        @full_graph.push(output)
      else
        puts output
      end

    end

    if @options[:save]
      puts "writing to #{output_path}"
      File.open(output_path, "w") { |f| f.puts(JSON.generate(@full_graph)) }
    end
  end
  if @options[:save]
    ActiveRecord::Base.connected_to(role: :writing) do
      @checkpoint.update(last_checkpointed_id: Repository.where(nwo: repo_nwo).first.github_repository_id)
    end
  end
end

def fetch_dependencies(parent_repo, package_name: nil, package_manager: nil, depth: @options[:depth], start: Time.now)
  return nil if depth == 0
  return nil if package_name.nil? || package_manager.nil?

  if check_if_timeout(parent_repo, start)
    puts "timing out!"
    log_repo(:timedout, parent_repo)
    exit
  end

  puts "working at depth #{depth} on package '#{package_name}' from #{package_manager}"

  package = Package.where(name: package_name, package_manager: package_manager).first
  return [] if package.nil?

  packages = (depth == @options[:depth] - 1) ? [package] : AbstractPackageDependency.where(dependent_id: package.id).packages

  output = []

  packages.each do |p|
    fetched_dependency_key = "#{p.package_manager.human_name}:#{p.name}"
    dependencies =
      if @already_fetched_dependencies.include?(fetched_dependency_key)
        "fetched"
      else
        @already_fetched_dependencies.push(fetched_dependency_key)
        fetch_dependencies(parent_repo, package_name: p.name, package_manager: p.package_manager, depth: depth - 1, start: start)
      end

    output.push({
      package_name: p.name,
      ecosystem: p.package_manager.human_name,
      repo_nwo: p.repository_nwo,
      dependencies: dependencies
    })
  end

  return output
end

def check_if_timeout(repo_nwo, start)
  if @options[:save] && duration_elapsed?(start)
    log_repo(:timedout, repo_nwo)
    return true
  end
  return false
end

def log_repo(reason, repo_nwo)
  log_reasons = [:timedout, :missing, :empty]
  raise unless log_reasons.include?(reason)

  log_path = Rails.root.join("script/one_off/archive_export/.#{reason}_repos.txt")
  File.open(log_path, "a") { |f| f.puts("#{repo_nwo}") }
  puts "repo #{repo_nwo} written to #{log_path}"
end

def duration_elapsed?(start_time)
  return Time.now - start_time > @options[:timeout]
end

def run_export
  puts "Starting export of #{@options[:repo]}"
    generate_graph(@options[:repo])
  puts "All done!"
end

def clean_dir
  clear_lists = [".timedout_repos.txt", ".missing_repos.txt", ".empty_repos.txt"]
  dir_path = File.expand_path(@options[:dir])

  clear_lists.each do |file|
   file_path = File.expand_path(dir_path + "/#{file}")
   next unless File.exist?(file_path)
   repos_to_clear = File.open(file_path).read.split("\n")

   repos_to_clear.each do |repo_nwo|
    path = File.expand_path(dir_path + "/#{repo_nwo.gsub("/", "~")}.json")
    if File.exist?(path)
      File.delete(path)
      puts "deleted #{path} (seen in #{file})"
    end
   end
  end

  Dir.foreach(dir_path) do |file|
    if file.match?(/.+~.+\.json/)
      file_path = File.expand_path(dir_path + "/#{file}")

      if File.zero?(file_path)
        File.delete(file_path)
        puts "deleted empty file #{file_path}"
      end
    end
  end
end

case @options[:mode]
when :clean
  clean_dir
when :run
  run_export
else
  run_export
end
