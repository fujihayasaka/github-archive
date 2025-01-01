#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Pull dependencies and transitive dependencies for specific repositories
# Usage: script/one_off/archive_data_export.rb
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

MAX_THREADS = 8
TIMEOUT = 10.minutes
MAX_REPOS_TEST = 5

@options = { mode: :run, test: true, save: false, max_tree_depth: 50, num_of_repos: nil,
             specific_repo: nil, start_line: nil, stop_cycles: true, clean_dir: nil,
             timeout: TIMEOUT, threads: MAX_THREADS, format_dir: nil,
           }
OptionParser.new do |opts|
  opts.on("-t", "--testsave", "Only test on the first #{MAX_REPOS_TEST} repos and save output") do |flag|
    @options[:test] = true
    @options[:save] = true
  end

  opts.on("-s", "--save", "Run through input file and save output") do |flag|
    @options[:test] = false
    @options[:save] = true
  end

  opts.on("-r=REPO", "--repo=REPO", "Generate graph for specific repo") do |repo|
    @options[:specific_repo] = repo
  end

  opts.on("-l=LINE", "--line=LINE", "Start from specific line number in input file") do |line|
    @options[:start_line] = line.to_i
  end

  opts.on("-d=DEPTH", "--depth=DEPTH", "Set max tree depth") do |depth|
    @options[:max_tree_depth] = depth.to_i
  end

  opts.on("-n=NUM", "--num=NUM", "Set max # of repos to iterate through") do |num|
    @options[:num_of_repos] = num.to_i
  end

  opts.on("-c", "--cycle", "Allow cycles to occur") do |flag|
    @options[:stop_cycles] = false
  end

  opts.on("-e=DIR", "--clean=DIR", "Set mode to clean and clean out given directory") do |dir|
    @options[:mode] = :clean
    @options[:clean_dir] = dir
  end

  opts.on("-f=DIR", "--format=DIR", "Format json files in given directory to be valid json") do |dir|
    @options[:mode] = :format
    @options[:format_dir] = dir
  end

  opts.on("-h=NUM", "--threads=NUM", "Set # of threads to use") do |num|
    @options[:threads] = num.to_i
  end

  opts.on("-x=NUM", "--timeout=NUM", "Set # of minutes before timing out") do |num|
    @options[:timeout] = num.to_i.minutes
  end
end.parse!(Array(ARGV))

@checkpoint = Checkpoint.find_or_create_by(name: "archive_data_export")

def return_dependencies(repo_nwo, package: nil, parent_repo: nil, parent_package: nil, depth: @options[:max_tree_depth], output_path: nil)
  ActiveRecord::Base.connected_to(role: :analytics) do
    return [] if depth == 0
    repo = Repository.where(nwo: repo_nwo).first
    if repo.nil?
      log_repo_missing(repo_nwo) unless output_path.nil?
      return []
    end

    start = Time.now
    puts "working at depth #{depth} on #{repo_nwo} package (#{package}) from parent repo (#{parent_repo})"

    manifests = nil
    manifests = Manifest.where(repository_id: repo.id, name: package).pluck(:id) if package.present?
    manifests = Manifest.where(repository_id: repo.id).pluck(:id) if manifests.nil?

    if manifests.nil?
      log_repo_missing(repo_nwo) unless output_path.nil?
      return []
    end

    selection = []
    manifests.in_groups_of(10, false) do |ids|
      selection.concat(ManifestDependency.where(manifest_id: ids).select(:requirements, :package_name, :package_manager, :exact_version))
    end

    selection = selection.uniq
    return [] if selection.empty?

    dependencies = []

    if output_path.present?
      sub_threads = []
      sub_thread_count = 0
      sub_thread_semaphore = Mutex.new
      sub_slice_size = (selection.count / 5.to_f).ceil

      selection.each_slice(sub_slice_size) do |slice|
        sub_threads << Thread.new do
          sub_thread_id = 0
          sub_thread_semaphore.synchronize do
            sub_thread_count += 1
            sub_thread_id = sub_thread_count
            puts "starting sub thread #{sub_thread_count} in #{repo_nwo}"
          end

          graph = graph_selection(slice, start, repo_nwo: repo_nwo, package: package, parent_repo: parent_repo, parent_package: parent_package, depth: depth, output_path: output_path)

          sub_thread_semaphore.synchronize do
            dependencies[sub_thread_id] = graph
          end
        end
      end
      sub_threads.each(&:abort_on_exception).each(&:join)

      dependencies.compact!.flatten!
    else
      dependencies = graph_selection(selection, start, repo_nwo: repo_nwo, package: package, parent_repo: parent_repo, parent_package: parent_package, depth: depth, output_path: output_path)
    end

    return nil if check_if_timeout(repo_nwo, start, output_path) && output_path.present?

    dependencies
  end
end

def graph_selection(selection, start, repo_nwo:, package:, parent_repo:, parent_package:, depth:, output_path:)
  dependencies = []

  selection.each do |md|
    return [] if check_if_timeout(repo_nwo, start, output_path)

    fetch_nwo = Package.where(package_manager: md.package_manager, name: md.package_name).where("repository_id_certainty >= #{PackageToRepoMapping::Certainty.minimum_required_for_display}").first&.repository_nwo

    next if (fetch_nwo == parent_repo) && (md.package_name == parent_package) && @options[:stop_cycles]

    output = {
      package_name: md.package_name,
      package_version: md.exact_version.nil? ? md.requirements : md.exact_version,
      ecosystem: md.package_manager.human_name,
      repo_nwo: fetch_nwo,
      dependencies: return_dependencies(fetch_nwo, package: md.package_name, parent_repo: repo_nwo, parent_package: package, depth: depth - 1)
    }

    return [] if check_if_timeout(repo_nwo, start, output_path)

    if output_path.nil?
      dependencies.push(output)
    else
      puts output if @options[:test]
      File.open(output_path, "a") { |f| f.puts("#{output.to_json},") } if @options[:save]
      dependencies = 1 # hack to make method return something at top level
    end
  end

  return dependencies
end

def check_if_timeout(repo_nwo, start, output_path)
  if @options[:save] && duration_elapsed?(start)
    log_repo_timeout(repo_nwo) if output_path
    return true
  end
  return false
end

def log_repo_timeout(repo_nwo)
  log_path = Rails.root.join("script/one_off/archive_export/.timedout_repos.txt")
  File.open(log_path, "a") { |f| f.puts("#{repo_nwo}") }
  puts "repo #{repo_nwo} written to #{log_path}"
end

def log_repo_missing(repo_nwo)
  log_path = Rails.root.join("script/one_off/archive_export/.missing_repos.txt")
  File.open(log_path, "a") { |f| f.puts("#{repo_nwo}") }
  puts "repo #{repo_nwo} written to #{log_path}"
end

def duration_elapsed?(start_time)
  return Time.now - start_time > @options[:timeout]
end

def run_export
  @options[:num_of_repos] = MAX_REPOS_TEST if @options[:num_of_repos].nil? && @options[:test]

  if @options[:specific_repo].nil?
    file_path = Rails.root.join("script/one_off/archive_repos_list.txt")
    @repos = File.open(file_path).read.split("\n")
    if @options[:start_line]
      line_number = @options[:start_line] <= 1  ? 0 : (@options[:start_line] - 1)
      @repos = @repos[line_number...]
    end
    @repos = @repos[0...@options[:num_of_repos]] unless @options[:num_of_repos].nil?
    puts "Processing #{@repos.count} repos"
  else
    @repos = [@options[:specific_repo]]
  end

  threads = []
  thread_count = 0
  thread_semaphore = Mutex.new
  slice_size = (@repos.count / @options[:threads].to_f).ceil

  @repos.each_slice(slice_size) do |slice|
    threads << Thread.new do
      thread_semaphore.synchronize do
        thread_count += 1
        puts "starting thread #{thread_count}"
      end
      slice.each do |repo|
        output_path = Rails.root.join("script/one_off/archive_export/#{repo.gsub("/", "~")}.json")
        # Clear out file if it already exists
        File.delete(output_path) if File.exist?(output_path)
        deps = return_dependencies(repo, output_path: output_path)
        if deps == 1 || deps&.include?(1)
          if @options[:save]
            puts "output written to #{output_path}"
            @checkpoint.update(last_checkpointed_id: Repository.where(nwo: repo).first.id) unless (@options[:test] || @options[:specific_repo])
          end
        else
          puts "no output for #{repo} or timeout occured."
        end
      end
    end
  end
  threads.each(&:abort_on_exception).each(&:join)

  puts "All done!"
end

def clean_dir
  clear_lists = [".timedout_repos.txt", ".missing_repos.txt"]
  dir_path = File.expand_path(@options[:clean_dir])

  clear_lists.each do |file|
   file_path = File.expand_path(dir_path + "/#{file}")
   repos_to_clear = File.open(file_path).read.split("\n")

   repos_to_clear.each do |repo_nwo|
    path = File.expand_path(dir_path + "/#{repo_nwo.gsub("/", "~")}.json")
    if File.exist?(path)
      File.delete(path)
      puts "deleted #{path}"
    end
   end
  end
end

def format_dir
  dir_path = File.expand_path(@options[:format_dir])
  Dir.foreach(dir_path) do |file|
    if file.match?(/.+~.+\.json/)
      file_path = File.expand_path(dir_path + "/#{file}")

      if File.zero?(file_path)
        File.delete(file_path)
        puts "deleted empty file #{file_path}"
        next
      end

      File.open(file_path, "r+") do |content|
        lines = content.each_line.to_a

        # add brackets to beginning and end to make valid json
        has_beginning_bracket = lines.first.starts_with?("[")
        has_ending_bracket = lines.last.ends_with?("]")

        lines.prepend("[") unless has_beginning_bracket
        lines.push("]") unless has_ending_bracket

        unless has_beginning_bracket && has_ending_bracket
          content.rewind
          content.puts(lines.join)
        end

        puts "processed #{file_path}"
      end
    end
  end
end

case @options[:mode]
when :clean
  clean_dir
when :run
  run_export
when :format
  format_dir
else
  run_export
end
