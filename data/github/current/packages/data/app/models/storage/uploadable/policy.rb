# typed: false
# frozen_string_literal: true

module Storage
  module Uploadable
    module Policy
      extend ActiveSupport::Concern

      module ClassMethods
        def act_on_storage_uploadable?
          GitHub.storage_cluster_enabled?
        end

        # Returns a Time instance that indicates when a `Storage::Purge` object
        # created for this Uploadable should be scheduled for final deletion.
        # Defaults to an hour later than the archived Repository retention interval,
        # computed as an offset of `Time.now`
        def purge_at
          Time.now + ::RepositoryBulkPurgeJob.expiration_period + 1.hour
        end

        def storage_auth_token(user, meta, expires: nil, repository: nil, key: nil)
          expires ||= 1.hour
          if user
            user.signed_auth_token(scope: storage_auth_scope(meta), expires: expires.from_now)
          else
            GitHub::Authentication::GitAuth::SignedAuthToken.generate(
              repo: repository,
              scope: storage_auth_scope(meta),
              expires: expires.from_now,
              data: {
                "member" => "repo:#{repository.id}:#{repository.nwo}",
                "proto" => "ssh",
                "deploy_key" => key.id
              }
            )
          end
        end

        def storage_verify_token(token, meta)
          if GitHub::Authentication::GitAuth::SignedAuthToken.valid_format?(token)
            return GitHub::Authentication::GitAuth::SignedAuthToken.verify(
              token: token,
              scope: storage_auth_scope(meta),
              repo: @repo,
            )
          end
          User.verify_signed_auth_token(token: token, scope: storage_auth_scope(meta))
        end

        def storage_disk_usage(conditions)
          blob_ids = where(conditions).pluck(:storage_blob_id)

          blob_ids.each_slice(10000).sum { |ids| Storage::Blob.where(id: ids).sum(:size) }
        end

        def storage_auth_scope(meta)
          path_info = meta[:path_info]
          if path_info.blank?
            GitHub.logger.info(
              "Empty auth scope",
              {
                "code.function": __method__,
                "gh.storage_uploadable.meta": meta.inspect
              }
            )
            raise "Empty auth scope"
          end

          ctype = meta[:original_type] || meta[:content_type]
          return path_info if ctype.blank?

          size = determine_auth_scope_size(ctype, meta)
          attrs = [path_info, ctype, size]
          auth_scope_allowlist = Set.new([:upload_url])

          meta.sort.each do |(k, v)|
            next unless auth_scope_allowlist.include?(k)
            attrs << v
          end

          attrs.compact!
          attrs.join(":")
        end

        def determine_auth_scope_size(ctype, meta)
          return 0 if ctype == "url"
          (meta[:original_size] || meta[:size]).to_i
        end
      end

      def storage_policy(actor: nil, repository: nil)
        raise NotImplementedError, "#{self.class} needs #storage_policy"
      end

      def storage_external_url(_ = nil)
        storage_policy.download_url
      end

      def storage_verify_path
        "#{self.class.uploadable_policy_path}/#{id}"
      end

      def storage_provider
        prov = read_attribute(:storage_provider)
        prov.blank? ? :default : prov.to_sym
      end

      def storage_transition_ready?
        storage_blob_accessible?
      end

      def storage_blob_accessible?
        raise NotImplementedError
      end

      # returns the absolute URL for the alambic uploader app to fetch after a
      # successful upload.
      def storage_api_url
      end
    end
  end
end
