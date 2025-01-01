# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Marketing::Solutions::Pages::OverviewPageTest < GitHub::TestCase
  setup do
    skip if GitHub.enterprise?

    enable_feature_flag(:contentful_response_validation)
  end

  def valid_page_stub
    Site::Contentful::Marketing::Solutions::ContentTypes::ContainerPage.stubs(:get_raw_json_for).returns(JSON.parse(File.read(Rails.root.join("test/fixtures/site/contentful/solutions/overview.json"))))
  end

  def invalid_page_stub
    Site::Contentful::Marketing::Solutions::ContentTypes::ContainerPage.stubs(:get_raw_json_for).returns(JSON.parse(File.read(Rails.root.join("test/fixtures/site/contentful/solutions/overview-no-hero.json"))))
  end

  context "validate!" do
    test "passes to the cache with valid entry data" do
      valid_page_stub

      subject = Site::Contentful::Marketing::Solutions::Pages::OverviewPage.new
      subject.expects(:save_page_data_in_cache).once
      subject.revalidate
    end

    test "skips invalid entry data" do
      invalid_page_stub

      subject = Site::Contentful::Marketing::Solutions::Pages::OverviewPage.new
      subject.expects(:save_page_data_in_cache).never
      subject.revalidate
    end
  end
end
