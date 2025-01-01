# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "transfer_test_helper"

class StorageUserAssetGistAssetBackfillerTest < GitHub::TestCase
  skip_enterprise
  skip_in_multitenant_mode

  fixtures do
    @user = create(:user)
    @random_user = create(:user)
  end

  def described_class
    Storage::UserAssetTransfer::GistAssetBackfiller
  end

  def create_gist(contents)
    # Note that the `after_creeate` hook `:assign_upload_container_id_to_user_assets` will be skipped here due to
    # `GitHub.context[:actor_id]` being nil. We will call `backfill_upload_container_ids` manually in the tests
    # For more info, check packages/data/app/models/upload_container/gist_dependency.rb#L23
    GistHelpers.generate(contents: contents, user: @user, public: false)
  end

  def mount_content(asset)
    { name: "file#{asset.id}.md", value: %Q(<img src="#{GitHub.gist_url}/assets/#{asset.user_id}/#{asset.guid}">) }
  end

  def with_gist_user(user, upload_container: nil, update_upload_container_id: false)
    args = { uploader: @user }
    args.merge!(upload_container ? { upload_container: upload_container } : { upload_container_type: Gist.name })

    assets = create_list(:user_asset, 2, args)
    contents = assets.map { |asset| mount_content(asset) }
    internal_gist = create_gist(contents)

    UserAsset.where(id: assets.map(&:id)).update_all(upload_container_id: internal_gist.id) if update_upload_container_id

    files_text = internal_gist.sorted_files.map(&:async_raw_data).map(&:value).join("")
    urls = described_class.extract_urls_from_text(files_text)

    backfiller_proc = ->(gist = internal_gist) { described_class.backfill_upload_container_ids(gist, user, urls) }

    yield(assets, internal_gist, backfiller_proc)
  end

  context "#backfill_upload_container_ids" do
    test "backfills upload_container_id if actor is owner of user assets" do
      with_gist_user(@user) do |assets, gist, backfiller_proc|
        backfiller_proc.call
        assets.each do |asset|
          asset.reload
          assert_equal gist.id, asset.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if actor is not owner of user assets" do
      with_gist_user(@random_user) do |assets, _, backfiller_proc|
        backfiller_proc.call
        assets.each do |asset|
          asset.reload
          assert_nil asset.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if user asset already belongs to a given Gist" do
      with_gist_user(@user, update_upload_container_id: true) do |assets, original_gist, backfiller_proc|
        contents = assets.map { |asset| mount_content(asset) }
        new_gist = create_gist(contents)
        backfiller_proc.call(new_gist)

        assets.each do |asset|
          asset.reload
          refute_equal new_gist.id, asset.upload_container_id
          assert_equal original_gist.id, asset.upload_container_id
        end
      end
    end

    test "doesn't backfill upload_container_id if upload_container is not a Gist" do
      repo = create(:repository)
      with_gist_user(@user, upload_container: repo) do |assets, _, backfiller_proc|
        backfiller_proc.call

        assets.each do |asset|
          asset.reload
          assert_equal repo, asset.upload_container
        end
      end
    end
  end
end
