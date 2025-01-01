# typed: false
# frozen_string_literal: true

module Api::Serializer::UploadableDependency
  def policy_hash(policy, options = nil)
    return nil unless policy
    hash = policy.policy_hash
    hash.delete(:asset)
    if u = policy.storage_policy_api_url
      hash[:asset_url] = url(u)
    end
    hash
  end

  def mobile_policy_hash(policy, options = nil)
    return nil unless policy
    serialized_options = Api::SerializerOptions.from(options)
    hash = policy.policy_hash
    # Only override asset_upload_url if the policy has one to begin with.
    # The Alambic policy doesn't require a final request to get the asset
    # details.
    if hash[:asset_upload_url].present? && serialized_options[:url].present?
      hash[:asset_upload_url] = serialized_options[:url]
    end
    hash
  end

  def mobile_asset_hash(policy, options = nil)
    return nil unless policy
    hash = policy.asset_hash
    hash
  end
end
