# typed: false
# frozen_string_literal: true

module Storage
  module Uploadable
    module ClusterPolicy
      def storage_cluster_url(policy)
        Storage.not_implemented!(policy, self, :storage_cluster_url)
      end

      def storage_download_path_info(policy)
        raise NotImplementedError, "#{self.class} needs #storage_download_path_info(policy)"
      end

      def storage_upload_path_info(policy)
        raise NotImplementedError, "#{self.class} needs #storage_upload_path_info(policy)"
      end

      def storage_cluster_download_token(policy, expires: nil)
        if !policy.actor && !(policy.repository && policy.key)
          raise ArgumentError, "This #{self.class} storage policy needs an actor or repository and key to create a token for downloads."
        end

        self.class.storage_auth_token(policy.actor, {
          path_info: storage_download_path_info(policy),
        }, expires: expires, repository: policy.repository, key: policy.key)
      end

      def storage_cluster_upload_source_url
        @storage_cluster_upload_source_url
      end

      def storage_cluster_upload_source_url=(value)
        @storage_cluster_upload_source_url = value
      end

      def storage_cluster_upload_token_params
        h = {
          size: size,
          content_type: content_type,
        }

        if u = storage_cluster_upload_source_url
          h[:upload_url] = u
          h[:original_type] = "url"
        end

        h
      end

      def storage_cluster_upload_token(policy, expires: nil)
        if !policy.actor && !(policy.repository && policy.key)
          raise ArgumentError, "This #{self.class} storage policy needs an actor or repository and key to create a token for downloads."
        end

        # If not proivded we configure an expiration time long enough for uploading big files when
        # connections with limitted bandwidth are used.
        expires ||= 3.hours
        params = storage_cluster_upload_token_params.merge(policy.remote_auth_params)
        params[:path_info] = storage_upload_path_info(policy)
        self.class.storage_auth_token(policy.actor, params, expires: expires, repository: policy.repository, key: policy.key)
      end

      def storage_download_content_type
        ctype = try(:content_type)
        ctype.present? ? ctype : "application/octet-stream"
      end
    end
  end
end
