
# typed: true
# frozen_string_literal: true

module TransferTestHelper
  def stub_s3_client_call_with_acl(acl, asset)
    GitHub.stubs(:s3_production_data_access_key).returns("access_key")
    GitHub.stubs(:s3_production_data_secret_key).returns("secret_key")

    key = "#{asset.user_id}/#{asset.id}-#{asset.guid}#{File.extname(asset.name)}"
    Aws::S3::Client.any_instance.stubs(:put_object_acl)
      .with(
        acl: acl,
        bucket: "github-test-user-asset-6210df",
        key: key
      )
      .once
  end

  def create_draft_asset_url(asset)
    "https://github.com/orgs/org/projects/1/assets/#{asset.user_id}/#{asset.guid}"
  end

  def create_unrelated_asset_url(asset)
    "https://user-assets.githubusercontent.com/#{asset.user_id}/#{asset.guid}"
  end

  def create_active_record_relation(assets)
    UserAsset.where(id: assets.map(&:id))
  end

  def draft_body_with_assets(asset)
    <<~TEXT
      This is a draft issue with an image:

      <img src="#{create_draft_asset_url(asset)}" />

      Please review and provide feedback.

      <img src="#{create_draft_asset_url(asset)}" />

      <img src="#{create_unrelated_asset_url(asset)}" />

      https://www.example.com/contact-us
    TEXT
  end
end
