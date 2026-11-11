# typed: true
# frozen_string_literal: true

# Builds a token from an SSH request that can be used for the Git LFS API.
#
#   # Request the Git LFS authentication header for a remote of
#   # git@github.com:owner/repo.git
#   $ ssh github.com git-lfs-authenticate owner/repo.git download {oid}
#
# GitAuth::GitLFS assumes that the GitAuth API has already confirmed that
# the SSH key is valid for the member, that the repo exists, and that the member
# has access to the repo.
module GitAuth
  class GitLFS
    EXPIRATION = {
      "upload" => 6.hours,
      "download" => 10.minutes,
    }

    attr_reader :expires, :operation

    def initialize(operation:, repository:, actor:, deploy_key:, protocol:)
      @operation = operation
      @repository = repository
      @actor = actor
      @deploykey = deploy_key
      @protocol = protocol

      if @actor.nil?
        @actor = writable_owner_for_repository(@repository)
        @member = "repo:#{@repository.id}:#{@repository.name_with_display_owner}"
      else
        @member = "user:#{@actor.id}:#{@actor.display_login}"
      end

      @expires = EXPIRATION[operation].from_now
    end

    def writable_owner_for_repository(repo)
      if repo.owner.organization?
        repo.owner.members(action: :admin).order(:created_at).reject(&:suspended?).first
      else
        repo.owner
      end
    end

    def response
      {
        href: response_href,
        header: response_header,
        expires_at: expires.utc.iso8601,
        expires_in: (expires - Time.now).to_i,
      }
    end

    def response_href
      "#{GitHub.lfs_server_url}/#{@repository.name_with_display_owner}"
    end

    def response_header
      h = {
        Authorization: "RemoteAuth #{token}",
      }

      if @deploykey
        h[:"Github-Deploy-Key"] = @deploykey.id.to_s
      end

      h
    end

    def token
      Media::Token.gitauth_token_for_actor(@deploykey || @actor, scope, @repository, expires)
    end

    def scope
      ["lfs", @repository.id, @operation, @deploykey&.id].compact.join(":")
    end
  end
end
