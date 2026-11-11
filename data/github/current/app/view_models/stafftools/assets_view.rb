# typed: true
# frozen_string_literal: true

module Stafftools
  class AssetsView < StorageBlobView
    attr_reader :asset

    def references
      @references ||= @asset.references.limit(100)
    end

    def storage_object
      @asset
    end

    private

    def link_to_storage_object
      urls.stafftools_asset_path(@asset.oid)
    end
  end
end
