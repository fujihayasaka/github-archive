# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiAcceptedMediaTypesTest < GitHub::TestCase
  def test_accepts_default_api_semantic_version_by_default
    media_type_strings = [
      "*/*",
      "text/plain; charset=utf-8",
    ]
    accepted = Api::AcceptedMediaTypes.new(media_type_strings)
    assert accepted.accepts_semantic_version?(Api::MediaType::DefaultSemanticVersion)
  end

  def test_accepts_valid_api_version
    media_type_strings = [
      "*/*",
      "text/plain; charset=utf-8",
      "application/vnd.github.beta+json",
    ]
    accepted = Api::AcceptedMediaTypes.new(media_type_strings)
    assert accepted.accepts_semantic_version?(:beta)
    refute accepted.accepts_semantic_version?(:v3)

    media_type_strings << "application/vnd.github.v3"
    accepted = Api::AcceptedMediaTypes.new(media_type_strings)
    assert accepted.accepts_semantic_version?(:v3)

    media_type_strings << "application/vnd.github.v4"
    accepted = Api::AcceptedMediaTypes.new(media_type_strings)
    assert accepted.accepts_semantic_version?(:v4)

    Api::MediaType.stub_const(:SemanticVersions, Api::MediaType::SemanticVersions << "superman-preview") do
      media_type_strings << "application/vnd.github.superman-preview"
      accepted = Api::AcceptedMediaTypes.new(media_type_strings)
      assert accepted.contains_preview?
    end
  end

  def test_versions_returns_empty_array_when_no_version_is_specified
    media_type_strings = [
      "application/json",
    ]
    api_media_types = Api::AcceptedMediaTypes.new(media_type_strings)

    assert_equal [], api_media_types.semantic_versions
  end

  def test_implicility_accepts_default_version_when_no_other_version_is_specified
    accepted = Api::AcceptedMediaTypes.new([])
    assert accepted.accepts_semantic_version?(Api::MediaType::DefaultSemanticVersion)

    accepted = Api::AcceptedMediaTypes.new(["*/*", "text/plain; charset=utf-8"])
    assert accepted.accepts_semantic_version?(Api::MediaType::DefaultSemanticVersion)

    bogus_media_type = "application/vnd.github.bogus+json"
    accepted = Api::AcceptedMediaTypes.new([bogus_media_type])
    assert accepted.accepts_semantic_version?(Api::MediaType::DefaultSemanticVersion)
  end

  def test_implicility_accepts_default_version_when_preview_version_is_specified
    Api::MediaType.stub_const(:SemanticVersions, Api::MediaType::SemanticVersions << "supergirl-preview") do
      valid_media_type = "application/vnd.github.supergirl-preview+json"
      accepted = Api::AcceptedMediaTypes.new(valid_media_type)
      assert accepted.accepts_semantic_version?(Api::MediaType::DefaultSemanticVersion)
      refute accepted.accepts_semantic_version?(:beta)
    end
  end

  def test_api_versions
    Api::MediaType.stub_const(:SemanticVersions, Api::MediaType::SemanticVersions + %w[a-preview b-preview]) do
      media_types = Api::AcceptedMediaTypes.new("application/vnd.github.invalid-preview.idl+json")
      assert_equal [:"v3"], media_types.api_semantic_versions

      media_types = Api::AcceptedMediaTypes.new(["application/vnd.github.a-preview.idl+json", "application/vnd.github.b-preview.idl+json"])
      assert_equal [:"a-preview", :"b-preview"], media_types.api_semantic_versions

      media_types = Api::AcceptedMediaTypes.new([
        "application/vnd.github.a-preview.idl+json",
        "application/vnd.github.b-preview.idl+json",
        "application/vnd.github.a-preview.idl+json",
      ])
      assert_equal [:"a-preview", :"b-preview"], media_types.api_semantic_versions

      media_types = Api::AcceptedMediaTypes.new([
        "application/vnd.github.b-preview.idl+json",
        "application/vnd.github.b-preview.idl+json",
        "application/vnd.github.a-preview.idl+json",
      ])
      assert_equal [:"a-preview", :"b-preview"], media_types.api_semantic_versions
    end
  end
end
