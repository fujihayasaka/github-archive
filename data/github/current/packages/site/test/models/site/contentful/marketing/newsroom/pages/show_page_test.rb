# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Marketing::Newsroom::Pages::ShowPageTest < GitHub::TestCase
  setup do
    skip if GitHub.enterprise?

    enable_feature_flag(:contentful_response_validation)
  end

  def valid_page_stub
    Site::Contentful::Marketing::Newsroom::ContentTypes::ContainerPage.stubs(:get_raw_json_for).returns(JSON.parse(File.read(Rails.root.join("test/fixtures/site/contentful/newsroom/show-page-valid.json"))))
  end

  def invalid_page_stub
    Site::Contentful::Marketing::Newsroom::ContentTypes::ContainerPage.stubs(:get_raw_json_for).returns(JSON.parse(File.read(Rails.root.join("test/fixtures/site/contentful/newsroom/show-page-invalid-no-published-date.json"))))
  end

  context "validate!" do
    test "passes to the cache with valid entry data" do
      valid_page_stub

      subject = Site::Contentful::Marketing::Newsroom::Pages::ShowPage.new(slug: "/newsroom/press-releases/agent-mode")
      subject.expects(:save_page_data_in_cache).once
      subject.revalidate
    end

    test "stops the cache with invalid entry data" do
      invalid_page_stub

      subject = Site::Contentful::Marketing::Newsroom::Pages::ShowPage.new(slug: "/newsroom/press-releases/agent-mode")
      subject.expects(:save_page_data_in_cache).never
      subject.revalidate
    end
  end
end
