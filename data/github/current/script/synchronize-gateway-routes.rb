#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

require "digest"
require "open3"
require "optparse"
require "sorbet-runtime"

def assert_environment_variable_set(name)
  if ENV[name].nil? || T.must(ENV[name]).empty?
    puts "Required environment variable #{name} is not set. Exiting."
    exit 1
  end

  ENV[name]
end

github_token = assert_environment_variable_set("GITHUB_TOKEN")
base_directory = assert_environment_variable_set("BASE_DIRECTORY")
source_repository_name = assert_environment_variable_set("SOURCE_REPOSITORY_NAME")
source_commit = assert_environment_variable_set("SOURCE_COMMIT")
destination_repository_name = assert_environment_variable_set("DESTINATION_REPOSITORY_NAME")
pull_request_number = assert_environment_variable_set("PULL_REQUEST_NUMBER")

module ProcessWrapper
  extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

  include Kernel

  sig { params(command: String).returns(String) }
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

  sig { params(repo_path: String, text: String).returns(String) }
  def git(repo_path, text)
    safe_system("git -C \"#{repo_path}\" #{text}")
  end

  sig { params(command: String).returns(Process::Status) }
  def get_exit_status(command)
    _, _, status = Open3.capture3(command)
    status
  end
end

class GatewayConfigSync
  extend T::Sig # rubocop:todo Sorbet/RedundantExtendTSig

  include Kernel

  include ProcessWrapper

  SOURCE_CONFIG_FILE = "app/api/gateway-routes.yaml"
  DESTINATION_CONFIG_FILE = "routes.yaml"

  attr_reader :base_directory,
              :source_repository_name,
              :destination_repository_name,
              :source_commit,
              :branch_name,
              :pull_request_number,
              :source_repo_path,
              :destination_repo_path

  sig do params(
    base_directory: String,
    source_repository_name: String,
    destination_repository_name: String,
    source_commit: String,
    pull_request_number: String
  ).void
  end
  def initialize(base_directory, source_repository_name, destination_repository_name, source_commit, pull_request_number)
    @base_directory = base_directory

    @source_repository_name = source_repository_name
    @destination_repository_name = destination_repository_name
    @source_commit = source_commit
    @branch_name = branch_name
    @pull_request_number = pull_request_number

    @source_repo_path = File.join(base_directory, source_repository_name)
    @destination_repo_path = File.join(base_directory, @destination_repository_name)

    @branch_name = "#{source_repository_name}-#{pull_request_number}-route-changes"
  end

  sig { params(args: String).void }
  def git_destination_repo(args)
    git(destination_repo_path, args)
  end

  def fetch_refs
    status = get_exit_status("git -C \"#{destination_repo_path}\" fetch origin #{branch_name}")
    if status.success?
      puts "Fetched existing ref #{branch_name} from #{destination_repository_name}."
    else
      puts "No ref matching #{branch_name} found in #{destination_repository_name}. A new branch should be created."
    end
  end

  def create_or_checkout_branch
    status = get_exit_status("git -C \"#{destination_repo_path}\" rev-parse origin/#{branch_name}")
    ref_found = status.success?

    if ref_found
      puts "Branch #{branch_name} already exists in #{destination_repository_name}. Proceeding with synchronization."
      git_destination_repo("checkout #{branch_name}")
    else
      puts "Branch #{branch_name} does not exist in #{destination_repository_name}. Creating a new branch."
      git_destination_repo("checkout main -b #{branch_name}")
    end
  end

  def synchronize_config_file
    destination_file_path = File.join(destination_repo_path, DESTINATION_CONFIG_FILE)

    source_config_blob = git(source_repo_path, "cat-file blob #{source_commit}:#{SOURCE_CONFIG_FILE}")
    destination_config_blob = git(destination_repo_path, "cat-file blob #{branch_name}:#{DESTINATION_CONFIG_FILE}")

    source_blob_hash = Digest::SHA256.hexdigest(source_config_blob)
    destination_blob_hash = Digest::SHA256.hexdigest(destination_config_blob)

    if source_blob_hash == destination_blob_hash
      puts "No changes between source and destination config files. No need to commit."
    else
      puts "Source routing file is different to routing config file. Committing new changes to #{destination_repository_name} repository."
      File.write(destination_file_path, source_config_blob)
      git_destination_repo("commit -am 'Adding gateway routes from PR ##{pull_request_number} in github/#{source_repository_name}'")
    end
  end
end

config_sync = GatewayConfigSync.new(base_directory, source_repository_name, destination_repository_name, source_commit, pull_request_number)
config_sync.fetch_refs
config_sync.create_or_checkout_branch
config_sync.synchronize_config_file
