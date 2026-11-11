# typed: false
# frozen_string_literal: true

module UserAsset::Quarantine
  PUBLIC_READ_ACL = "public-read"
  PRIVATE_ACL = "private"

  # Public: Makes the asset not visible to anyone on GitHub, but does not delete it
  # Built for Project Schaefer https://github.com/github/schaefer
  def quarantine(reason:)
    return false if GitHub.storage_cluster_enabled? || GitHub.multi_tenant_enterprise? || self.quarantining
    return false unless clear_from_cdn_cache

    current_acl = get_original_acl
    update_acl(PRIVATE_ACL) if current_acl != PRIVATE_ACL

    unless self.update(original_acl: current_acl, quarantining: true)
      begin
        # We revert the ACL back to what it was before the update failed
        update_acl(current_acl) if current_acl != PRIVATE_ACL
      rescue Aws::S3::Errors::ServiceError => e
        quarantine_warn_log("Unable to revert asset #{self.id} ACL to #{current_acl}", {
          "code.function": __method__,
          "exception.message": e.message,
        })
      end

      return false
    end

    instrument :quarantine, user_asset: self, reason: reason, user: self.uploader
    true
  rescue Aws::S3::Errors::ServiceError => e
    quarantine_warn_log("Unable to set asset #{self.id} ACL to private", {
      "code.function": __method__,
      "exception.message": e.message,
    })
    false
  end

  def unquarantine(reason:)
    return false if GitHub.storage_cluster_enabled? || GitHub.multi_tenant_enterprise?
    return false unless clear_from_cdn_cache

    update_acl(PUBLIC_READ_ACL) if is_legacy_asset? || self.original_acl == PUBLIC_READ_ACL

    unless self.update(quarantining: nil)
      begin
        # We revert the ACL back to what it was before the update failed
        update_acl(PRIVATE_ACL)
      rescue Aws::S3::Errors::ServiceError => e
        quarantine_warn_log("Unable to revert asset #{self.id} ACL to private", {
          "code.function": __method__,
          "exception.message": e.message
        })
      end

      return false
    end

    instrument :unquarantine, user_asset: self, reason: reason, user: self.uploader
    true
  rescue Aws::S3::Errors::ServiceError => e
    quarantine_warn_log("Unable to set asset #{self.id} ACL to public-read", {
      "code.function": __method__,
      "exception.message": e.message
    })
    false
  end

  def update_acl(acl)
    storage_s3_client.put_object_acl(
      bucket: storage_s3_bucket,
      key: storage_s3_key(nil),
      acl: acl,
    )
  end

  def get_original_acl
    grants = storage_s3_client.get_object_acl(
      bucket: storage_s3_bucket,
      key: storage_s3_key(nil),
    ).grants

    is_public = grants.any? do |grant|
      grant.grantee.uri == "http://acs.amazonaws.com/groups/global/AllUsers" &&
      grant.permission == "READ"
    end

    is_public ? PUBLIC_READ_ACL : PRIVATE_ACL
  end

  def is_legacy_asset?
    self.repository_id.nil? && self.upload_container_type.nil?
  end

  def clear_from_cdn_cache
    return false if GitHub.storage_cluster_enabled?

    urls = [storage_external_url]
    with_storage_provider(:default) do
      urls << storage_external_url
    end

    urls.compact.each do |url|
      PurgeFastlyUrlJob.perform_later("url" => url)
    end

    true
  end

  def quarantine_warn_log(msg, extra_context = {})
    GitHub.logger.warn(msg, { "code.namespace": "UserAsset::Quarantine" }.merge(extra_context))
  end
end
