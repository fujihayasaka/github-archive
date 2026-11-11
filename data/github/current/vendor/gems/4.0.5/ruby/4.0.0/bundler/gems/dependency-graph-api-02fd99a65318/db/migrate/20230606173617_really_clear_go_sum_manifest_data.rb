require "#{Rails.root}/lib/transitions/clear_manifest_data"

class ReallyClearGoSumManifestData < ActiveRecord::Migration[7.0]
  def up
    options = {
      filters: {
        filename: "go.sum",
        package_manager: ::Types::PackageManager.coerce("go"),
      },
      dry_run: false,
      manifest_batch_size: 100,
      dependency_batch_size: 1000,
    }

    ::Transitions::ClearManifestData.new(options).execute
  end

  def down
  end
end
