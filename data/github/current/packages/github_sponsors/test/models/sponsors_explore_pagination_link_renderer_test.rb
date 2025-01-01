# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsExplorePaginationLinkRendererTest < GitHub::TestCase
  fixtures do
    @collection = [:a, :b, :c].paginate(page: 1, per_page: 2)
    @pagination_options = WillPaginate::ViewHelpers.pagination_options
  end

  setup do
    @renderer = SponsorsExplorePaginationLinkRenderer.new
    @page_url = "/some/path"
    fake_template = stub(will_paginate_translate: nil, url_for: @page_url)
    @renderer.prepare(@collection, @pagination_options, fake_template)
  end

  context "#page_number" do
    test "includes Hydro click tracking in returned link HTML" do
      html = @renderer.page_number(2)

      doc = Nokogiri::HTML.fragment(html)
      link = doc.at_css("a[href='#{@page_url}']")
      refute_nil link
      hydro_data = JSON.parse(link["data-hydro-click"])
      assert_equal "sponsors.explore_pagination_click", hydro_data["event_type"]
      assert_equal 1, hydro_data.dig("payload", "current_page")
      assert_equal 2, hydro_data.dig("payload", "new_page")
    end

    test "omits link when given current page" do
      html = @renderer.page_number(1)

      doc = Nokogiri::HTML.fragment(html)
      assert_nil doc.at_css("a")
    end
  end

  context "#previous_or_next_page" do
    test "includes Hydro click tracking in returned link HTML" do
      html = @renderer.previous_or_next_page(2, "Next", "my-link")

      doc = Nokogiri::HTML.fragment(html)
      link = doc.at_css("a.my-link[href='#{@page_url}']")
      refute_nil link
      hydro_data = JSON.parse(link["data-hydro-click"])
      assert_equal "sponsors.explore_pagination_click", hydro_data["event_type"]
      assert_equal 1, hydro_data.dig("payload", "current_page")
      assert_equal 2, hydro_data.dig("payload", "new_page")
    end

    test "omits link when not given a page" do
      html = @renderer.previous_or_next_page(nil, "Previous", "my-link")

      doc = Nokogiri::HTML.fragment(html)
      assert_nil doc.at_css("a")
      element = doc.at_css(".my-link")
      refute_nil element
      assert_equal "Previous", element.text
    end
  end
end
