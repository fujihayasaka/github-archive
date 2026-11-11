# frozen_string_literal: true

# Helper methods and shared context for alert seeding and reset scripts.
#
# Usage:
#   require_relative "seed_helper"

SeedContext = Struct.new(:repo, :pull_request, :pull_request_for_sideeffect, :requester, :reviewer, keyword_init: true)

def running_on_localhost?
  # Make sure this is only run in a development Codespace environment, since it relies on specific test data and is not idempotent.
  unless Rails.env.development? && ENV["CODESPACES"].present?
    return false
  end

  host_without_port = GitHub.host_name_with_tenant.to_s.sub(/:\d+\z/, "")
  unless host_without_port.end_with?(".localhost")
    return false
  end

  true
end

def setup_context
  repo = Repository.find_by(name: "public-server", owner_login: "github")
  if repo.nil?
    puts "No repository found for github/public-server. This shouldn't happen as the repo is seeded by gh/gh codespace."
    return nil
  end

  pull_request = repo.issues.find_by_number(1)&.pull_request
  if pull_request.nil?
    puts "No pull request found for repo #{repo.full_name} with number 1.  Create 2 pull requests in http://github.localhost/github/public-server and run this script again."
    return nil
  end

  pull_request_for_sideeffect = repo.issues.find_by_number(2)&.pull_request
  if pull_request_for_sideeffect.nil?
    puts "No pull request found for repo #{repo.full_name} with number 2.  Create a pull request in http://github.localhost/github/public-server and run this script again."
    return nil
  end

  reviewer = User.find_by_login("monalisa")
  if reviewer.nil?
    puts "User monalisa not found. This shouldn't happen as the user is seeded by gh/gh codespace."
    return nil
  end
  requester = User.find_by_login("collaborator")

  if reviewer.nil?
    puts "User collaborator not found. This shouldn't happen as the user is seeded by gh/gh codespace."
    return nil
  end

  SeedContext.new(repo: repo, pull_request: pull_request, pull_request_for_sideeffect: pull_request_for_sideeffect, requester: requester, reviewer: reviewer)
end
