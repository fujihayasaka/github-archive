# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class ReferenceSorterTest < Minitest::Test
    def test_returns_a_unique_list_of_urls
      urls = [
        "https://abc.com/123",
        "https://abc.com/123 ",
        "https://abc.com/456",
        "https://abc.com/123/",
        "https://abc.com/123",
      ]
      assert_equal [
        "https://abc.com/123",
        "https://abc.com/456",
      ], ReferenceSorter.sorted_reference_list(urls.shuffle)
    end

    def test_does_not_error_on_nil_url
      urls = [nil]
      assert_equal [], ReferenceSorter.sorted_reference_list(urls.shuffle)
    end

    def test_orders_preferred_urls_on_top
      urls = [
        "https://github.com/jhipster/generator-jhipster/security/advisories/GHSA-mwp6-j9wf-968c",
        "https://nvd.nist.gov/vuln/detail/CVE-2019-16303",
        "https://github.com/jhipster/generator-jhipster/issues/10401",
        "https://github.com/jhipster/jhipster-kotlin/issues/183",
        "https://github.com/SudharakaP/generator-jhipster/pull/57",
        "https://github.com/jhipster/generator-jhipster/commit/f2cd27cf6810c5707459d342f88649f4b3d11c79",
        "https://hackerone.com/reports/685447",
        "https://another.com/random",
        "https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2019-16303",
        "https://nodesecurity.io/advisories/317",
        "https://www.jhipster.tech/2019/09/13/jhipster-release-6.3.0.html",
        "https://www.npmjs.com/advisories/317",
        "ftp://somecveshaveftpurls.pdf",
      ]

      10.times do
        unsorted = urls.shuffle
        random_index = rand(urls.length - 1)
        unsorted[random_index] = " #{unsorted[random_index]}"
        assert_equal urls, ReferenceSorter.sorted_reference_list(unsorted)
      end
    end
  end
end
