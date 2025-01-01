# typed: true
# frozen_string_literal: true

module Storage
  # This policy defines how files are stored and accessed using the Alambic's
  # legacy filesystem adapter.
  class ClusterPolicy < AlambicPolicy
    def download_url(query = nil)
      now = Time.now
      query ||= {}
      url = @uploadable.storage_cluster_url(self)

      expiration = query.delete(:expiration)
      token = if expiration && @uploadable.is_a?(UserAsset)
        @uploadable.storage_cluster_download_token(self, expires: expiration)
      else
        @uploadable.storage_cluster_download_token(self)
      end

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
        href: @uploadable.storage_cluster_url(self),
      }

      if token = @uploadable.storage_cluster_download_token(self)
        link[:header] = {
          "Authorization" => "RemoteAuth #{token}",
        }
      else
        link[:href] += "?token=0"
      end

      link
    ensure
      stats_timing(:download, start: now) if now
    end

    def lfs_upload_link
      {
        href: @uploadable.storage_cluster_url(self),
        header: {
          "Accept" => "application/vnd.github.smasher+json",
          "Authorization" => "RemoteAuth #{@uploadable.storage_cluster_upload_token(self)}",
        },
        expires_in: 1.hour.to_i,
      }
    end

    def asset_hash
      h = super

      if @uploadable.is_a?(UserAsset)
        h[:repository_id] = @uploadable.repository_id if @uploadable.repository_id

        h[:upload_container_type] = @uploadable.upload_container_type if @uploadable.upload_container_type
        h[:upload_container_id] = @uploadable.upload_container_id if @uploadable.upload_container_type && @uploadable.upload_container_id
      end

      h
    end

    # We overwrite the Policy.set_faraday_adapter to use a timeout of 3 hours (10800 seconds).
    # This aligns with the HAProxy configuration on GHES for alambic and ensures we allow enough time for large migration files on GHES.
    def self.set_faraday_adapter(*adapter_args)
      @@faraday = Faraday.new do |f| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
        f.request :multipart
        f.request :url_encoded
        f.options.timeout = 3.hours.to_i
        f.options.open_timeout = 3.hours.to_i
        # Faraday versions older than v1.0.0 don't have this option.  See https://github.ghe.com/github/octoshift/issues/9857.
        f.options.read_timeout = 3.hours.to_i if f.options.respond_to?(:read_timeout=)
        f.options.write_timeout = 3.hours.to_i
        f.adapter(*adapter_args)
      end
    end

    private

    def upload_header
      h = {
        "Accept" => "application/vnd.github.assets+json; charset=utf-8",
      }

      if token = @uploadable.storage_cluster_upload_token(self)
        h["GitHub-Remote-Auth"] = token
        if GitHub.enterprise?
          h["Authorization"] = "RemoteAuth #{token}"
        end
      end

      h
    end
  end
end
