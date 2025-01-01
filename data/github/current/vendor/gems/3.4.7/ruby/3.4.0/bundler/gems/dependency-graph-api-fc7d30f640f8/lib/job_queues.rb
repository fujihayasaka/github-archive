module DependencyGraphAPI
  module JobQueues
    # Plain in this case means "non-prefixed"
    def self.get_plain_queues
      manifest_queues = Types::PackageManager.map { |package_manager| :"manifest_#{package_manager}" }
      manifest_queues << :detect_manifest_vulnerabilities
      manifest_queues << :manifest_snapshots_npm
      other_queues = [
        :package,
        :snapshot_request,
        :default,
        :actions_package,
        :ospo_package_metadata,
        :manifest_deleted,
      ]
      manifest_queues + other_queues
    end

    def self.get_prefixed_queues
      all_queues = get_plain_queues
      delimiter = Rails.application.config.active_job[:queue_name_delimiter] || "_"
      prefix = Rails.application.config.active_job[:queue_name_prefix]
      all_queues.map { |queue| "#{prefix}#{delimiter}#{queue}" }
    end
  end
end
