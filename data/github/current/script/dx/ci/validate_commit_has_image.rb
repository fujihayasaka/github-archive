#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"

require_relative "subproject_container_helper"

current_dir = File.dirname(__FILE__)
subproject_config_contents = File.read(File.expand_path("../subproject-to-image-map.json", current_dir))
subproject_config_map = JSON.parse(subproject_config_contents)

matched = false
changed_files = get_changed_files
changed_files.each do |file|
  if subproject_config_map.include?(file)
    puts "Found subproject version file change: #{file}"
    matched = true

    sha = sha_from_file(file)

    sha_has_container_command = "docker manifest inspect #{subproject_config_map[file]}:#{sha}"
    stdout, stderr, status = Open3.capture3(sha_has_container_command)
    if !status.success?
      if stderr.include?("manifest unknown")
        STDERR.puts "ERROR:  The config on master for #{file} has an associated container.
        The new sha #{sha} for repository #{subproject_config_map[file]} does not have a container.
        Please ensure the sha has an associated container. A common pattern is to only build containers from commits to master/main for example:
        https://gh.io/create-ci-action-to-build-your-container
        You may need to choose the merge commit sha to get a corresponding container"
      else
        STDERR.puts "Unknown error encountered while checking for container for #{sha} for repository #{subproject_config_map[file]}."
        STDERR.puts "Stderr: #{stderr}"
      end
      exit 1
    else
      puts "Found container for #{sha} for repository #{subproject_config_map[file]}"
    end
  end
end

if !matched
  puts "No subproject version file changes found"
else
  puts "All subproject version file changes have associated containers"
end
