# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class CacheSkusTest < GitHub::TestCase
    test "it sets no SKUs for an invalid vscs_target + location combo" do
      CacheSkus.call
      assert_equal [], Codespaces::Skus::Cache.get(:development, "EastUs")
    end

    test "it sets specific SKUs per valid vscs_target + locations" do
      CacheSkus.call
      dev_skus = Codespaces::Skus::Cache.get(:development, "WestUs2").map { |s| s[:name] }
      prod_skus = Codespaces::Skus::Cache.get(:production, "WestUs2").map { |s| s[:name] }

      assert_includes dev_skus, :premiumLinux32gb
      assert_includes prod_skus, :premiumLinux32gb
      assert_includes dev_skus, :premiumLinux
      assert_includes prod_skus, :premiumLinux
    end
  end
end
