# typed: true
# frozen_string_literal: true

require "asset_bundles"

# This class will verify that all required bundles exist in the manfiest as well
# as on disk. The verification only happens during a production deploy.
# This check is meant to prevent the pod from booting successfully.

if Rails.env.production? && GitHub.role_from_host == :fe
  AssetBundles.verify_assets!
end
