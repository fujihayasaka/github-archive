#!/usr/bin/env ruby
#
# Imports a manifest by fetching the contents from GitHub.com and enqueuing a ProcessManifestJob.
# Usage: script/dev/send-process-manifest-job -r REPO -f FILE

require_relative "../../config/environment"

require "base64"
require "json"
require "net/http"
require "optparse"

options = { file: nil, repo_nwo: nil }
begin
  OptionParser.new do |opts|
    opts.banner = "Usage: bin/rails r script/dev/import-manifest [options]"

    opts.on("-f", "--file FILE", String, "Path to the manifest you'd like to import, relative to the repo root") do |file|
      options[:file] = file
    end

    opts.on("-r", "--repo-nwo NWO", String, "GitHub repository name-with-owner of the repository to import to") do |nwo|
      options[:repo_nwo] = nwo
    end
  end.parse!
rescue OptionParser::MissingArgument => e
  puts e.message
  puts "Run with --help to list arguments"
end

def make_request(url)
  uri = URI("https://api.github.com/#{url}")
  req = Net::HTTP::Get.new(uri)
  req["Accept"] = "application/vnd.github+json"
  req["Authorization"] = "Bearer #{gh_token}"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |https|
    https.request(req)
  end

  if res.code != "200"
    puts "There was a problem making the request."
    puts "URL: #{uri}"
    puts "#{res.code} #{res.message}"
  end

  JSON.parse(res.body, symbolize_names: true)
end

def gh_token
  token = ENV["GITHUB_TOKEN"]
  if token.blank?
    puts "GITHUB_TOKEN environment variable is not set."
    puts "This script will still work, but you will only be able to access public repositories."
  end
  token
end

def fetch_manifest_content(repo_nwo, file)
  response = make_request("repos/#{repo_nwo}/contents/#{file}")
  Base64.decode64(response[:content])
end

begin
  existing_repo = Repository.find_by(nwo: options[:repo_nwo])
  if existing_repo
    owner_id = existing_repo.github_owner_id
    repo_id = existing_repo.github_repository_id
    puts "Importing to existing repository #{options[:repo_nwo]} (#{owner_id}/#{repo_id})"
  else
    # There might be a collision, but it's unlikely
    # This is just for development anyway
    repo_id = rand(100..999)

    repos_by_same_owner = Repository.where("nwo LIKE ?", "#{options[:repo_nwo].split("/").first}/%")
    if repos_by_same_owner.count > 0
      owner_id = repos_by_same_owner.first.github_owner_id
      puts "Owner exists in database, using ID #{owner_id}"
    else
      owner_id = rand(100..999)
    end
  end

  manifest_filename = File.basename(options[:file])
  manifest_path = File.dirname(options[:file])
  contents = fetch_manifest_content(options[:repo_nwo], options[:file])

  message = {
    manifest_file: {
      filename: manifest_filename,
      path: manifest_path,
      git_ref: "0000000000000000000000000000000000000000",
      pushed_at: {
        seconds: Time.now.to_i,
      }
    },
    manifest_contents: contents,
    repository_id: repo_id,
    owner_id: owner_id,
    repository_nwo: options[:repo_nwo],
    repository_stargazer_count: 0,
    repository_private: false,
    repository_fork: false,
    is_backfill: false
  }

  ProcessManifestJob.perform_later(message)

  puts "Enqueued ProcessManifestJob!"

rescue => e
  puts "Error importing manifest!"
  puts e.message
  puts DependencyGraph::SqlUtils::StackFilter.first_significant_frame(e.backtrace)
  exit
end
