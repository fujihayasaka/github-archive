# typed: strict
# frozen_string_literal: true

require "test_helper"

class RepositoryImageDependencyTest < GitHub::TestCase
  context "#async_uses_custom_open_graph_image?" do
    test "true when repo is public and has a custom OG image" do
      repo = create(:repository)
      create(:repository_image, repository: repo)

      assert repo.async_uses_custom_open_graph_image?.sync
      assert repo.uses_custom_open_graph_image?
    end

    test "false when repo is private and has a custom OG image" do
      repo = create(:private_repository)
      create(:repository_image, repository: repo)

      refute repo.async_uses_custom_open_graph_image?.sync
      refute repo.uses_custom_open_graph_image?
    end

    test "false when repo is public and has no custom OG image" do
      repo = create(:repository)

      refute repo.async_uses_custom_open_graph_image?.sync
      refute repo.uses_custom_open_graph_image?
    end
  end

  context "#async_open_graph_image_url" do
    test "returns custom image URL when repo is public and has a custom OG image" do
      repo = create(:repository)
      image = create(:repository_image, repository: repo)

      assert_equal image.storage_external_url(nil),
        repo.async_open_graph_image_url(viewer: nil).sync
      assert_equal image.storage_external_url(nil),
        repo.open_graph_image_url(nil)
      assert_equal image.storage_external_url(nil),
        repo.custom_open_graph_image_url(nil)
    end

    test "returns owner avatar URL when repo is private and has a custom OG image" do
      owner = create(:user)
      repo = create(:private_repository, owner: owner)
      create(:repository_image, repository: repo)

      assert_equal owner.primary_avatar_url(400),
        repo.async_open_graph_image_url(viewer: nil).sync
      assert_equal owner.primary_avatar_url(400),
        repo.open_graph_image_url(nil)
      assert_nil repo.custom_open_graph_image_url(nil)
    end

    test "returns owner avatar URL when repo is public and has no custom OG image" do
      owner = create(:organization)
      repo = create(:repository, owner: owner)
      owner.stubs(:ip_allowlist_enabled?).returns(true)

      assert_equal owner.primary_avatar_url(400),
        repo.async_open_graph_image_url(viewer: nil).sync
      assert_equal owner.primary_avatar_url(400),
        repo.open_graph_image_url(nil)
      assert_nil repo.custom_open_graph_image_url(nil)
    end

    if !GitHub.enterprise?
      test "returns enhanced opengraph image url when there is no custom one" do
        owner = create(:user)
        repo = create(:public_repository, owner: owner)

        assert_equal repo.og_image_url,
          repo.async_open_graph_image_url(viewer: nil).sync
        assert repo.show_enhanced_og_image?
        assert_nil repo.custom_open_graph_image_url(nil)
      end
    end

    test "returns ghost avatar URL when repo is missing its owner and has no custom image" do
      owner = create(:user)
      repo = create(:repository, owner: owner)
      owner.delete

      assert_equal User.ghost.primary_avatar_url(400),
        repo.reload.async_open_graph_image_url(viewer: nil).sync
      assert_equal User.ghost.primary_avatar_url(400),
        repo.open_graph_image_url(nil)
      assert_nil repo.custom_open_graph_image_url(nil)
    end
  end

  context "#og_image_url" do
    test "it returns enhanced opengraph image url with correct cache key" do
      user = create(:user)
      repo = create(:repository, name: "opengraph test", owner: user)

      # calculate expected cache key from specific resource attributes
      cache_key = Digest::SHA256.hexdigest(
        [
          repo.updated_at
        ].join(":")
      )

      # enhanced opengraph url with expected cache slug
      image_url = "#{GitHub.og_image_generator_base_url}/#{cache_key}#{repo.permalink(include_host: false)}"

      assert_equal image_url, repo.og_image_url
    end
  end

  context "#show_enhance_og_image?" do
    test "it returns false if enterprise" do
      repo = create(:public_repository)
      GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests
      refute repo.show_enhanced_og_image?
    end

    test "it returns false if private", skip_enterprise: true do
      repo = create(:private_repository)
      refute repo.show_enhanced_og_image?
    end

    test "it returns false if owner has IP allowlist enabled", skip_enterprise: true do
      user = create(:user)
      org = create(:organization, admin: user)
      repo = create(:public_repository, owner: org)
      repo.owner.enable_ip_allowlist(actor: user)
      refute repo.show_enhanced_og_image?
    end

    test "it returns true", skip_enterprise: true do
      repo = create(:public_repository)
      assert repo.show_enhanced_og_image?
    end
  end
end
