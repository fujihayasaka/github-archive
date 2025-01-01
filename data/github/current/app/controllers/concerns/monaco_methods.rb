# typed: true
# frozen_string_literal: true

module MonacoMethods
  def monaco_worker_paths(asset_bundles, web_worker_path)
    types = %w[editor css html json ts]
    types.each_with_object({}) do |type, hash|
      bundle_name = AssetBundles.new.expand_bundle_name("monaco-#{type}-worker.js")
      hash[type.to_sym] = web_worker_path.call(bundle_name)
    end
  end
end
