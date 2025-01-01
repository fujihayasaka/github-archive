# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::Marketing::Startups::Pages::PartnersTest < GitHub::TestCase
  require_cassettes_for_external_http_connections

  setup do
    skip if GitHub.enterprise?

    @partners_list = VCR.use_cassette("contentful/startups-partners-list-all") do
      Site::Contentful::Marketing::Startups::StartupPartner.all
    end

    @partners_page = Site::Contentful::Marketing::Startups::Pages::Partners.new
  end

  context "#fetch_data_from_contentful" do
    test "returns list of startup partners" do
      VCR.use_cassette("contentful/startup-partners-show-partners") do
        expected_partners = @partners_list.map(&:to_json)

        result = @partners_page.fetch_data_from_contentful

        assert_equal expected_partners, result[:partners]
      end
    end
  end

  context "#cache_key" do
    test "builds the right cache key" do
      assert_equal "site.swp.startups.partners", @partners_page.cache_key
    end
  end
end
