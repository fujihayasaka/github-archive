# typed: strict
# frozen_string_literal: true

module GitHub
  module Unsullied
    autoload :Comparison,                       "github/unsullied/comparison"
    autoload :Editor,                           "github/unsullied/editor"
    autoload :FilesCollection,                  "github/unsullied/files_collection"
    autoload :HTML,                             "github/unsullied/html"
    autoload :Page,                             "github/unsullied/page"
    autoload :PagesCollection,                  "github/unsullied/pages_collection"
    autoload :Wiki,                             "github/unsullied/wiki"
    autoload :CachedAssetUrlRewriter,           "github/unsullied/cached_asset_url_rewriter"
    autoload :CachedEnterpriseAssetUrlRewriter, "github/unsullied/cached_enterprise_asset_url_rewriter"
    autoload :CachedDotcomAssetUrlRewriter,     "github/unsullied/cached_dotcom_asset_url_rewriter"
  end
end
