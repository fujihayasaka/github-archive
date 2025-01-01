#!/usr/bin/env ruby

require_relative "../../config/environment"
require "rack"
require "github-proto-repositories"
require "webrick"

class StubRepositoriesHandler

  # Will return a list of repositories for the given NWOs, or create them if they don't exist.
  def find_repositories_by_name(req, env)
    repositories = []

    req.nwos.each do |nwo|
      repo = find_or_create_repository(nwo)
      owner, name = nwo(nwo)
      repositories << { id: repo.github_repository_id, owner_id: repo.github_owner_id, owner_login: owner, name: name }
    end

    {
      repositories: repositories
    }
  end

  # Will return a list of repositories for the given IDs, but will **NOT** create them if they don't exist.
  def find_repositories(req, env)
    repositories = []

    req.ids.each do |id|
      repo = Repository.find_by(github_repository_id: id)
      next unless repo
      owner, name = nwo(repo.nwo)
      repositories << { id: repo.github_repository_id, owner_id: repo.github_owner_id, owner_login: owner, name: name }
    end

    {
      repositories: repositories
    }
  end

  private

  def nwo(nwo)
    s = nwo.split("/")
    return s[0], s[1]
  end

  def find_or_create_repository(nwo, public: true)
    repo = Repository.find_by(nwo: nwo)
    return repo unless repo.nil?

    # There might be a collision, but it's unlikely
    # This is just for development anyway
    repo_id = rand(100..999)

    repos_by_same_owner = Repository.where("nwo LIKE ?", "#{nwo.split("/").first}/%")
    if repos_by_same_owner.count > 0
      owner_id = repos_by_same_owner.first.github_owner_id
    else
      owner_id = rand(100..999)
    end

    Repository.create!(nwo: nwo, github_owner_id: owner_id, github_repository_id: repo_id, public: public)
  end
end

if File.exist?("/etc/dg.codespace-compose")
  puts "Since this codespace is running in codespace-compose mode, not starting the Monolith Repository service stub"
  exit(0)
end

handler = StubRepositoriesHandler.new
service = GitHub::Proto::Repositories::V1::RepositoriesAPIService.new(handler)

port = ENV.fetch("MONOLITH_API_PORT", 3859)
path_prefix = "/twirp/#{service.full_name}"

puts "Mounting Repositories service at http://127.0.0.1:#{port}/#{path_prefix}"

server = WEBrick::HTTPServer.new(Port: port)
server.mount path_prefix, Rack::Handler::WEBrick, service
server.start
