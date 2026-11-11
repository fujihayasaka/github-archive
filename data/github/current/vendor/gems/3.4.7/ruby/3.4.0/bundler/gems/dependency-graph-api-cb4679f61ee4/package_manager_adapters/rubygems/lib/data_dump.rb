require "fileutils"
require "httparty"

class DataDump
  include Logging

  HOST      = "https://s3-us-west-2.amazonaws.com/rubygems-dumps/"
  PATH      = "production/public_postgresql"
  RETENTION = 2

  def initialize(data_dir:)
    @data_dir = Pathname.new(data_dir)
  end

  def download_latest
    FileUtils.mkdir_p(@data_dir)

    download unless already_downloaded?

    cleanup
  end

  def output
    @output ||= data_dir.join(latest_version.local_filename)
  end

  private

  attr_reader :data_dir

  def download
    logger.info("Downloading data dump from #{latest_version.url}")

    File.open(output, "wb") do |f|
      HTTParty.get(latest_version.url, stream_body: true) do |fragment|
        f.write(fragment)
      end

      f.close
    end
  end

  def cleanup
    File.delete(*delete_targets)
  end

  def already_downloaded?
    File.exist?(output)
  end

  def latest_version
    @latest_version ||= versions.max_by(&:last_modified_at)
  end

  def versions
    HTTParty.get(HOST, query: { prefix: PATH })
      .fetch("ListBucketResult")
      .fetch("Contents")
      .map { |v| Version.new(*v.values_at("Key", "LastModified")) }
  end

  def delete_targets
    all_dumps.sort[0..-(RETENTION + 1)]
  end

  def all_dumps
    Dir.glob(@data_dir.join("*"))
  end

  Version = Struct.new(:key, :last_modified) do
    def url
      URI.join(HOST, key)
    end

    def last_modified_at
      Time.parse(last_modified)
    end

    def local_filename
      "rubygems_dump_#{date}.sql.gz.tar"
    end

    private

    def date
      key.split("/")[-2]
    end
  end
end
