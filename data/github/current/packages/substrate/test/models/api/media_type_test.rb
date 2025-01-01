# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiMediaTypeTest < GitHub::TestCase
  def test_parses_json_mimetype
    mime = Api::MediaType.new "application/json"
    assert mime.api?
    assert_equal Api::MediaType::DefaultSemanticVersion, mime.api_semantic_version
    refute mime.explicit_api_semantic_version?(Api::MediaType::DefaultSemanticVersion)
    assert mime.api_params.empty?
    assert_equal "github.#{Api::MediaType::DefaultSemanticVersion}", mime.to_http_header
  end

  def test_parses_github_mimetype
    mime = Api::MediaType.new "application/vnd.github+json"
    assert mime.api?
    assert_equal Api::MediaType::DefaultSemanticVersion, mime.api_semantic_version
    refute mime.explicit_api_semantic_version?(Api::MediaType::DefaultSemanticVersion)
    assert mime.api_params.empty?
    assert_equal "github.#{Api::MediaType::DefaultSemanticVersion}; format=json", mime.to_http_header
  end

  def test_parses_github_resource_mimetype
    mime = Api::MediaType.new "application/vnd.github-gist+json"
    assert mime.api?
    assert mime.api_params.empty?
    assert_equal "github.#{Api::MediaType::DefaultSemanticVersion}; format=json", mime.to_http_header
  end

  def test_parses_github_resource_mimetype_with_param
    mime = Api::MediaType.new "application/vnd.github-gist.full+json"
    assert mime.api?
    assert_equal Api::MediaType::DefaultSemanticVersion, mime.api_semantic_version
    refute mime.explicit_api_semantic_version?(Api::MediaType::DefaultSemanticVersion)
    assert_equal [:full], mime.api_params.to_a
    assert_equal "github.#{Api::MediaType::DefaultSemanticVersion}; param=full; format=json", mime.to_http_header
  end

  def test_parses_github_resource_mimetype_with_version_and_param
    mime = Api::MediaType.new "application/vnd.github-gist.v3.full+json"
    assert mime.api?
    assert_equal :v3, mime.api_semantic_version
    assert mime.explicit_api_semantic_version?(:v3)
    assert_equal [:full], mime.api_params.to_a
    assert_equal "github.v3; param=full; format=json", mime.to_http_header
  end

  def test_parses_github_mimetype_and_checks_if_preview_version
    Api::MediaType.stub_const(:SemanticVersions, Api::MediaType::SemanticVersions << "superman-preview") do
      mime = Api::MediaType.new "application/vnd.github-gist.superman-preview.full+json"
      assert mime.api?
      assert_equal :"superman-preview", mime.api_semantic_version
      assert mime.preview_semantic_version?
    end
  end

  def test_parses_github_resource_mimetype_with_big_param
    mime = Api::MediaType.new "application/vnd.github-gist.abc.full+json"
    assert mime.api?
    assert_equal Api::MediaType::DefaultSemanticVersion, mime.api_semantic_version
    refute mime.explicit_api_semantic_version?(Api::MediaType::DefaultSemanticVersion)
    assert mime.api_params.include?(:abc)
    assert mime.api_params.include?(:full)
    header = mime.to_http_header
    segments = header.split(";").each { |part| part.strip! }
    assert_equal "github.#{Api::MediaType::DefaultSemanticVersion}", segments.shift
    assert_match /^param=(abc\.full|full\.abc)$/, segments.shift
    assert_equal "format=json", segments.shift
    assert_nil segments.shift
  end

  def test_parses_simple_type
    mime = Api::MediaType.new("text/plain")
    assert_equal "text",  mime.main_type
    assert_equal "plain", mime.sub_type
    assert_equal "",      mime.suffix
    assert_equal({},      mime.params)
    assert !mime.api?
    assert_equal Api::MediaType::DefaultSemanticVersion, mime.api_semantic_version
    refute mime.explicit_api_semantic_version?(Api::MediaType::DefaultSemanticVersion)
    assert mime.api_params.empty?
    assert_equal "unknown", mime.to_http_header
  end

  def test_parses_bad_type
    mime = Api::MediaType.new("*; q=.2")
    assert_equal "",   mime.sub_type
    assert_equal "*",  mime.main_type
    assert_equal "",   mime.suffix
    assert_equal "",   mime.vendor
    assert_equal ".2", mime.params["q"]
    assert !mime.vendor?
    assert !mime.api?
    assert_equal Api::MediaType::DefaultSemanticVersion, mime.api_semantic_version
    refute mime.explicit_api_semantic_version?(Api::MediaType::DefaultSemanticVersion)
    assert mime.api_params.empty?
    assert_equal "unknown", mime.to_http_header
  end

  def test_parses_simple_type_with_parameters
    mime = Api::MediaType.new("text/plain; charset=utf-8")
    assert_equal "text",  mime.main_type
    assert_equal "plain", mime.sub_type
    assert_equal "",      mime.suffix
    assert_equal "utf-8", mime.params["charset"]
    assert !mime.vendor?
    assert !mime.api?
    assert_equal Api::MediaType::DefaultSemanticVersion, mime.api_semantic_version
    refute mime.explicit_api_semantic_version?(Api::MediaType::DefaultSemanticVersion)
    assert mime.api_params.empty?
    assert_equal "unknown", mime.to_http_header
  end

  def test_parses_vendor_type
    mime = Api::MediaType.new("application/vnd.abc+xml; charset=utf-8")
    assert_equal "application", mime.main_type
    assert_equal "vnd.abc",     mime.sub_type
    assert_equal "xml",         mime.suffix
    assert_equal "utf-8",       mime.params["charset"]
    assert_equal "abc",         mime.vendor
    assert !mime.api?
    assert mime.vendor?
    assert_equal "unknown", mime.to_http_header
  end
end
