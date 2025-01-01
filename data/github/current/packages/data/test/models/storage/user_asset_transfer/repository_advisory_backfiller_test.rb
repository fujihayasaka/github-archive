# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "transfer_test_helper"

class StorageUserAssetRepositoryAdvisoryAssetBackfillerTest < GitHub::TestCase
  skip_enterprise
  skip_in_multitenant_mode

  fixtures do
    @user = create(:user)
    @repo = create :public_repository, owner: @user
  end

  def with_repository_advisory(user, external_assets: nil, upload_container: nil, update_upload_container_id: false)
    GitHub.context.push(actor_id: user.id)

    args = { uploader: user }
    args.merge!(upload_container ? { upload_container: upload_container } : { upload_container_type: RepositoryAdvisory.name })

    assets = external_assets ? external_assets : create_list(:user_asset, 2, args)
    urls = assets.map { |asset| "#{GitHub.url}/user-attachments/assets/#{asset.guid}" }
    description = urls.map { |url| url }.join("\n")
    advisory = create(:repository_advisory, repository: @repo, author: user, state: "open", description: description)

    UserAsset.where(id: assets.map(&:id)).update_all(upload_container_id: advisory.id) if update_upload_container_id

    yield(assets, advisory)
  end

  context "#backfill_upload_container_ids" do
    test "backfills upload_container_id if actor is owner of user assets" do
      with_repository_advisory(@user) do |assets, repository_advisory|
        assets.each do |asset|
          asset.reload
          assert_equal repository_advisory.id, asset.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if the actor is not the owner of the user assets" do
      asset_owner = create(:user)
      assets = create_list(:user_asset, 2, uploader: asset_owner)
      with_repository_advisory(@user, external_assets: assets) do |assets, _|
        assets.each do |asset|
          asset.reload
          assert_nil asset.upload_container_type
          assert_nil asset.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if the actor is not the owner of the user assets in another advisory" do
      asset_owner = create(:user)
      with_repository_advisory(asset_owner) do |other_user_assets, other_user_advisory|
        other_user_assets.each do |asset|
          # Ensure that upload_container_id is set for these models.
          asset.reload
        end
        with_repository_advisory(@user, external_assets: other_user_assets) do |assets, advisory|
          assets.each do |asset|
            asset.reload
            assert_equal RepositoryAdvisory.name, asset.upload_container_type
            refute_equal advisory.id, asset.upload_container_id
            assert_equal other_user_advisory.id, asset.upload_container_id
          end
        end
      end
    end

    test "doesn't backfill upload_container_id if user asset already belongs to a given RepositoryAdvisory" do
      with_repository_advisory(@user, update_upload_container_id: true) do |assets, repository_advisory|
        urls = assets.map { |asset| "#{GitHub.url}/user-attachments/assets/#{asset.guid}" }
        description = urls.map { |url| url }.join("\n")
        repository_advisory_new = create(:repository_advisory, repository: @repo, author: @user, state: "open", description: description)
        assets.each do |asset|
          asset.reload
          refute_equal repository_advisory_new.id, asset.upload_container_id
          assert_equal repository_advisory.id, asset.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if upload_container is not a RepositoryAdvisory" do
      repo = create(:repository)
      with_repository_advisory(@user, upload_container: repo) do |assets, _|
        assets.each do |asset|
          asset.reload
          assert_equal repo, asset.upload_container
        end
      end
    end

  end
end
