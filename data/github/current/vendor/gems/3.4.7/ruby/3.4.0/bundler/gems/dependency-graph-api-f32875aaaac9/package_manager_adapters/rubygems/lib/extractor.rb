require "logging"
require "httparty"
require "partitioned_range"
require "models"

class Extractor
  include Logging

  CHECKPOINT = "ruby-gems-max-id"

  def self.run(**args)
    new(**args).run
  end

  def initialize(sink_proxy_url: "http://localhost:7777")
    @sink = Sink.new(sink_proxy_url)
  end

  def run
    Models::DownloadCount.generate
    import_gem_versions
    sink.set_checkpoint(CHECKPOINT, Models::Version.maximum(:id).to_i)
  end

  private

  attr_reader :sink

  def import_gem_versions
    each_version_batch do |batch|
      attributes = batch.map do |version|
        next unless version.package_name.present?
        logger.info "Processing package #{version.package_name} (ID: #{version.id})"

        {
          package_manager: :rubygems,
          package_name:    version.package_name,
          version:         version.package_version,
          description:     version.description,
          authors:         version.authors,
          download_count:  version.downloads,
          external_id:     version.external_id.to_s,
          source_url:      version.source_url,
          home_url:        version.home_url,
          docs_url:        version.docs_url,
          unpublished_at:  version.yanked_at&.to_i,
          published_at:    version.built_at&.to_i,
          dependencies:    version.dependencies.map { |dependency|
            {
              package_name: dependency.package_name,
              requirements: dependency.requirements,
              scope:        (dependency.development? ? :development : :runtime),
            }
          }
        }
      end

      sink.publish_package_releases(attributes.compact)
    end
  end

  def versions
    Models::Version.order(:id)
      .includes(:rubygem, :linkset, :download_count, :dependencies)
      .where("versions.id > ?", sink.get_checkpoint(CHECKPOINT))
  end

  def each_version_batch(&block)
    partitions = PartitionedRange.new(
      min: versions.minimum(:id),
      max: versions.maximum(:id),
      partitions: Etc.nprocessors,
    )

    threads = partitions.map do |partition|
      Thread.new do
        versions
          .where(id: partition)
          .find_in_batches(batch_size: 100)
          .each(&block)
      end
    end

    threads.each(&:abort_on_exception).each(&:join)
  end

  class Sink
    include HTTParty

    def initialize(base_uri)
      @base_uri = base_uri
    end

    def set_checkpoint(name, value)
      HTTParty.put("#{base_uri}/checkpoints/#{name}", {
        body: { value: value }
      })
    end

    def get_checkpoint(name)
      response = HTTParty.get("#{base_uri}/checkpoints/#{name}", {
        format: :plain
      })

      JSON.parse(response.body)["value"]
    end

    def publish_package_releases(package_releases)
      HTTParty.post("#{base_uri}/package_releases", {
        body: { package_releases: package_releases.to_json }
      })
    end

    private

    attr_reader :base_uri
  end
end
