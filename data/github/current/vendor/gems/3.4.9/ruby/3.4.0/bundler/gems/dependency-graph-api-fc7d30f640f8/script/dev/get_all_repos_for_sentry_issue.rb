#! /usr/bin/env ruby

require "json"
require "net/http"
require "uri"

##############
# get_all_repos_for_sentry_issue.rb
#
# Pulls all events for a given sentry issue and extracts repository id, distincts, and returns.
#
# Usage:
#
# The first argument is the Sentry PAT, the remaining params are the Sentry issue #s.
# Sentry PATs can be retrieved from https://sentry.io/settings/account/api/auth-tokens/
#
#   script/dev/get_all_repos_for_sentry_issue.rb <pat> 12345, 56789

pat = ARGV.shift

# rubocop:disable Security/Eval
args = eval("[#{ARGV.join(' ')}]")

def get_response(pat, string_uri)
  uri = URI.parse(string_uri)
  req = Net::HTTP::Get.new(uri)
  req["Content-Type"] = "application/json"
  req["Authorization"] = "Bearer #{pat}"

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
  end

  res.body
end

repository_ids = []
args.each do |issue_number|
  events = JSON.parse(get_response(pat, "https://sentry.io/api/0/issues/#{issue_number}/events/?cursor=0:0:1"))
  event_ids = events.map { |event| event["id"] }

  event_ids.each do |event_id|
    organization_slug = "github"
    project_slug = "dependency-graph-api" # this is the id associated with dependency-graph-api in Sentry
    event_data = JSON.parse(get_response(pat, "https://sentry.io/api/0/projects/#{organization_slug}/#{project_slug}/events/#{event_id}/"))
    repository_ids.push event_data["context"]["github_repository_id"]
  end
end

puts repository_ids.uniq.join("\n")
