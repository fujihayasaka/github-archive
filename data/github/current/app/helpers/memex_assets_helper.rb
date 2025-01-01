# typed: true
# frozen_string_literal: true

module MemexAssetsHelper
  class MemexAssetException < StandardError
    def initialize(msg = "Failed to parse Memex asset payload")
      super
    end
  end

  def memex_js_bundle
    T.bind(self, BundleHelper)
    javascript_bundle("memex")
  end
end
