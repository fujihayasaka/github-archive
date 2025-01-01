# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestImageDependencyTest < GitHub::TestCase
  setup do
    @pull = create(:pull_request, :disable_disk_access)
  end

  context "#async_og_image_url", skip_enterprise: true do
    test "it async returns nil if repo is private" do
      repo = @pull.repository
      repo.update!(private: true)

      assert_nil @pull.async_og_image_url.sync
    end

    test "it async returns enhanced opengraph image url with correct cache key" do
      repo = @pull.repository

      # calculate expected cache key from specific resource attributes
      cache_key = Digest::SHA256.hexdigest(
        [
          @pull.updated_at,
          @pull.issue.updated_at,
          repo.name,
          repo.owner_id,
        ].join(":")
      )

      # enhanced opengraph url with expected cache slug
      image_url = "#{GitHub.og_image_generator_base_url}/#{cache_key}#{@pull.permalink(include_host: false)}"

      assert_equal image_url, @pull.async_og_image_url.sync
    end
  end

  context "#og_image_url" do
    test "it returns enhanced opengraph image url with correct cache key" do
      repo = @pull.repository

      # calculate expected cache key from specific resource attributes
      cache_key = Digest::SHA256.hexdigest(
        [
          @pull.updated_at,
          @pull.issue.updated_at,
          repo.name,
          repo.owner_id,
        ].join(":")
      )

      # enhanced opengraph url with expected cache slug
      image_url = "#{GitHub.og_image_generator_base_url}/#{cache_key}#{@pull.permalink(include_host: false)}"

      assert_equal image_url, @pull.og_image_url
    end
  end
end
