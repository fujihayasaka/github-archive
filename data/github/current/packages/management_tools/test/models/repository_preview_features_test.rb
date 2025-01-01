# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryPreviewFeaturesTest < GitHub::TestCase
  fixtures do
    @github  = create(:organization, login: "github")

    @gh_pub  = create(:repository, owner: @github)
    @gh_priv = create(:private_repository, owner: @github)

    @pub  = create(:repository)
    @priv = create(:private_repository)
  end

  setup do
    GitHub.preview_features_enabled = true
  end

  test "is true for private GitHub repos" do
    assert @gh_priv.preview_features?
  end

  test "is false for public GitHub repos" do
    assert !@gh_pub.preview_features?
  end

  test "is false for any non-GitHub repo" do
    assert !@priv.preview_features?
    assert !@pub.preview_features?
  end

  test "is false for private GitHub repos if preview features are not enabled" do
    GitHub.preview_features_enabled = false
    assert !@gh_priv.preview_features?
  end
end
