class ManifestDeleter
  # Helper method to initialize and run with a Kafka message.
  def self.run!(job_params)
    self.new(job_params).run!
  end

  attr_accessor :deleted_manifest

  def initialize(job_params)
    raise ArgumentError, "message is empty" if job_params.blank?
    raise ArgumentError, "message must be a Hash" unless job_params.is_a?(Hash)
    raise ArgumentError, "invalid repository manifest coordinates" if job_params[:repository_id].nil?

    @deleted_manifest = job_params
  end

  def run!
    DependencyGraph.logger.with_named_tags({ "gh.repo.id" => deleted_manifest.fetch(:repository_id, "UNKNOWN") }) do
      repository = ActiveRecord::Base.connected_to(role: :reading) do
        Repository.find_by(github_repository_id: deleted_manifest[:repository_id])
      end

      return repo_not_found_error unless repository.present?

      manifest = Manifest.find_by(
        repository_id: repository.id,
        filename: deleted_manifest.dig(:manifest_file, :filename),
        path: deleted_manifest.dig(:manifest_file, :path)
      )

      return manifest_not_found_error unless manifest.present?

      if manifest.destroy
        # Obtain package names that remain after deleting the target manifest from the repository
        known_good_package_names = []
        ActiveRecord::Base.connected_to(role: :reading) do
          if DependencyGraph.use_normalized_tables?
            ManifestEntry
              .latest_revisions
              .joins(:manifest, manifest_package_version: :manifest_package).where({
              Manifest.table_name => {
                repository_id: repository.id,
                package_manager: manifest.package_manager.serialize
              }
            }).where.not(manifest_id: manifest.id).in_batches do |batch|
              known_good_package_names << batch.pluck("#{ManifestPackage.table_name}.package_name")
            end
          else
            ManifestDependency
              .latest_revisions
              .joins(:manifest).where({
              Manifest.table_name => {
                repository_id: repository.id,
                package_manager: manifest.package_manager.serialize
              }
            }).where.not(manifest_id: manifest.id).in_batches do |batch|
              known_good_package_names << batch.pluck(:package_name)
            end
          end
        end

        # Obtain unique package names tracked against this repository as "abstract dependencies"
        current_rab_package_names = []
        repository
          .abstract_dependencies
          .where(package_manager: manifest.package_manager)
          .in_batches { |batch| current_rab_package_names << batch.pluck(:package_name) }

        # Diff to obtain the no-longer-present packages and delete from RAB table in chunks
        eliminated_packages = current_rab_package_names.flatten.to_set - known_good_package_names.flatten.to_set
        eliminated_packages.each_slice(100) do |pkg_names|
          repository.abstract_dependencies
          .where(package_manager: manifest.package_manager, package_name: pkg_names)
          .destroy_all
        end

        return true
      else
        Instrument.increment("manifest_deleter.manifest_not_deleted")
        return log_error({
          log_message: "Manifest couldn't be deleted",
          filename: deleted_manifest.dig(:manifest_file, :filename),
          repository_id: repository.id,
          manifest_id: manifest&.id,
          path: deleted_manifest.dig(:manifest_file, :path),
        })
      end
    end
  end

  private

  def log_error(message)
    DependencyGraph.logger.error(message)
    false
  end

  def manifest_not_found_error
    # Don't instrument or log if the filename ends in .js
    # We'd like to avoid this because the Vintage dark-ship has increased the number of manifests we can't find because
    # our loose JS RegEx in dotcom results in a lot of JS file deletions being processed by Dependency Graph.
    return if deleted_manifest.dig(:manifest_file, :filename).match?(/\.js$/)

    Instrument.increment("manifest_deleter.manifest_not_found",
      manifest_type: deleted_manifest.dig(:manifest_file, :filename) || "UNKNOWN")

    return log_error({
      log_message: "Manifest not found by path and filename",
      repository_id: deleted_manifest.fetch(:repository_id, "UNKNOWN"),
      filename: deleted_manifest.dig(:manifest_file, :filename),
      path: deleted_manifest.dig(:manifest_file, :path)
    })
  end

  def repo_not_found_error
    Instrument.increment("manifest_deleter.repository_not_found")
    return log_error({
      log_message: "Repository not found by github_repository_id",
      repository_id: deleted_manifest.fetch(:repository_id, "UNKNOWN"),
    })
  end
end
