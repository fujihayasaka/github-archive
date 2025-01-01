#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"

require_relative "subproject_container_helper"

current_dir = File.dirname(__FILE__)
subproject_config_contents = File.read(File.expand_path("../subproject-to-image-map.json", current_dir))
subproject_config_map = JSON.parse(subproject_config_contents)

changed_files = get_changed_files
changed_files.each do |file|
  if subproject_config_map.include?(file)
    puts "Found subproject version file change: #{file}"

    sha = sha_from_file(file)

    # parse the service from config map value (i.e., ghcr.io/github/alambic/alambic)
    subproject_image = subproject_config_map[file].split("/").last

    # refresh OIDC token
    system("ruby #{current_dir}/../../ci/refresh-oidc-token.rb -c $HOME/.docker/config.json")

    # Mirror to octofactory
    pull_cmd = "docker pull #{subproject_config_map[file]}:#{sha}"
    pull_stdout, pull_stderr, pull_status = Open3.capture3(pull_cmd)
    if !pull_status.success?
      STDERR.puts "ERROR: unable to pull #{subproject_config_map[file]}:#{sha}"
      STDERR.puts "Stderr: #{pull_stderr}"
      exit 1
    end

    octofactory_url = "octofactory-ang.githubapp.com/github-subprojects"
    subproject_mirror_url_and_tag = "#{octofactory_url}/#{subproject_image}:#{sha}"
    tag_cmd = "docker tag #{subproject_config_map[file]}:#{sha} #{subproject_mirror_url_and_tag}"

    tag_stdout, tag_stderr, tag_status = Open3.capture3(tag_cmd)
    if !tag_status.success?
      STDERR.puts "ERROR: unable to tag #{subproject_config_map[file]}:#{sha} with #{subproject_mirror_url_and_tag}"
      STDERR.puts "Stderr: #{tag_stderr}"
      exit 1
    end

    push_cmd = "docker push #{subproject_mirror_url_and_tag}"
    push_stdout, push_stderr, push_status = Open3.capture3(push_cmd)
    if !push_status.success?
      STDERR.puts "ERROR: unable to push to mirror: #{subproject_mirror_url_and_tag}"
      STDERR.puts "Stderr: #{push_stderr}"
      exit 1
    end

    puts "The image was successfully pushed to the mirror: #{subproject_mirror_url_and_tag}"
  end
end
