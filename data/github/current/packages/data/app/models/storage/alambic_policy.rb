# typed: true
# frozen_string_literal: true

module Storage
  # This policy defines how files are stored and accessed using the Alambic's
  # legacy filesystem adapter.
  class AlambicPolicy < Policy
    def download_url(query = nil)
      now = Time.now
      query ||= {}
      url = @uploadable.storage_alambic_url(self)
      token = token_for_downloads
      query.update(token: token) if token
      query_string = query.empty? ? "" : "?#{query.to_query}"
      "#{url}#{query_string}"
    ensure
      stats_timing(:download, start: now) if now
    end

    alias metadata_url download_url

    def download_link
      now = Time.now
      link = {
        href: @uploadable.storage_alambic_url(self),
      }

      if token = token_for_downloads
        link[:header] = {
          "Authorization" => "RemoteAuth #{token}",
        }
      end

      link
    ensure
      stats_timing(:download, start: now) if now
    end

    def storage_supports_multi_part_upload
      false
    end

    def asset_hash
      h = @uploadable.storage_uploadable_attributes.update(
        size: @uploadable.size,
        content_type: @uploadable.content_type,
      )

      if @uploadable.respond_to?(:name)
        h[:name] = @uploadable.name
      end

      if @uploadable.respond_to?(:directory)
        h[:directory] = @uploadable.directory || ""
      end

      h
    end

    def upload_url
      @uploadable.creation_url || "invalid-url"
    end

    private

    def token_for_downloads
      @uploadable.storage_cluster_download_token(self)
    end

    def token_for_uploads
      @uploadable.storage_cluster_upload_token(self)
    end

    def upload_header
      h = {
        "Accept" => "application/vnd.github.assets+json; charset=utf-8",
      }

      if token = token_for_uploads
        h["GitHub-Remote-Auth"] = token
        if GitHub.enterprise?
          h["Authorization"] = "RemoteAuth #{token}"
        end
      end

      h
    end

    # There's no URL to mark after the upload to alambic has completed
    def asset_upload_url
    end
  end
end
