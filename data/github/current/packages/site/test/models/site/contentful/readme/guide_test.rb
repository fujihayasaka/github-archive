# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Readme::GuideTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  unless GitHub.enterprise?
    setup do
      @guide_angie = VCR.use_cassette("contentful/readme-guide-angie-jones-demystifying-developer-advocacy") do
        Site::Contentful::Readme::Guide.find("angie-jones-demystifying-developer-advocacy", include_unpublished: true)
      end
    end

    test "#name" do
      assert_equal "Angie Jones", @guide_angie.name
    end

    context "#project_name" do
      test "returns company name" do
        assert_equal "Applitools", @guide_angie.project_name
      end

      test "returns nil when company is not set" do
        @guide_angie.stubs(:company).returns(nil)

        assert_nil @guide_angie.project_name
      end
    end

    test "#label" do
      assert_equal "Angie Jones // Applitools", @guide_angie.label
    end
  end
end
