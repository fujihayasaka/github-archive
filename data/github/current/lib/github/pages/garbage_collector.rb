# typed: false
# frozen_string_literal: true

require "flipper"
require "github/config/flipper"
require "feature_management"
require "github/config/memcache"
require "github/config/notifications"
require "github/pages/management/delegate"
require "instrumentation"

class GitHub::Pages::GarbageCollector
  class Build
    attr_reader :path, :page_id, :revision

    def initialize(path)
      @path = path

      path_components = path.split("/")

      @page_id = path_components[-2].to_i
      @revision = path_components[-1]
    end
  end

  def self.run!
    gc = new

    GitHub.dogstats.distribution_time("pages.gc.runtime.dist") do
      return unless gc.enabled?

      # Collect build folder to clean
      garbage = gc.garbage

      # Delete the folders, one by one
      garbage.each do |build|
        next if build.page_id <= 0
        gc.delegate.log "Garbage collecting page_id=#{build.page_id} path=#{build.path}"
        gc.rm_rf(build.path)
      end
      GitHub.dogstats.count("pages.gc.collected", garbage.count)

      # Delete empty folders
      gc.delete_empty_folders unless GitHub.kube?
    end

    nil
  end

  attr_reader :delegate

  def initialize(delegate = nil)
    @delegate = (delegate || GitHub::Pages::Management::Delegate.new(logger: GitHub::Logger))
  end

  def host
    @host ||=
      if GitHub.enterprise?
        GitHub.local_pages_host_name
      else
        Socket.gethostname
      end
  end

  def garbage
    builds_by_page_id = builds.group_by(&:page_id)

    current_deployments = Set.new

    builds_by_page_id.keys.each_slice(1_000) do |page_ids|
      GitHub::Pages::GarbageCollector.deployed_revisions_with_replica_count(page_ids: page_ids, host: host).each do |id, built_revision|
        current_deployments << "#{id}_#{built_revision}"
      end
    end

    builds_by_page_id.flat_map do |page_id, builds|
      builds.reject do |build|
        current_deployments.include?("#{page_id}_#{build.revision}")
      end
    end
  end

  def self.deployed_revisions_with_replica_count(page_ids:, host:)
    GitHub::Pages::GarbageCollector.deployed_revisions_using_deployments(page_ids: page_ids, host: host) | GitHub::Pages::GarbageCollector.deployed_revisions_legacy(page_ids: page_ids, host: host)
  end

  def self.deployed_revisions_using_deployments(page_ids:, host:)
    results = ActiveRecord::Base.connected_to(role: :reading) do
      ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_ids: page_ids, host: host))
        SELECT page_deployments.page_id, page_deployments.revision FROM page_deployments
        INNER JOIN pages_replicas ON (page_deployments.id = pages_replicas.pages_deployment_id)
        INNER JOIN pages ON (page_deployments.page_id = pages.id)
        WHERE page_deployments.page_id IN (:page_ids)
        AND page_deployments.revision IS NOT NULL
        AND pages_replicas.host = :host
        GROUP BY page_deployments.page_id, page_deployments.revision
      SQL
    end
    Set.new(results)
  end

  def self.deployed_revisions_legacy(page_ids:, host:)
    results = ActiveRecord::Base.connected_to(role: :reading) do
      ApplicationRecord::Pages.connection.select_rows(Arel.sql(<<-SQL, page_ids: page_ids, host: host))
        SELECT pages.id, pages.built_revision FROM pages
        INNER JOIN pages_replicas ON (pages.id = pages_replicas.page_id)
        WHERE pages.id IN (:page_ids)
        AND pages.built_revision IS NOT NULL
        AND pages_replicas.pages_deployment_id IS NULL
        AND pages_replicas.host = :host
        GROUP BY pages.id, pages.built_revision
        ORDER BY NULL
      SQL
    end
    Set.new(results)
  end

  def builds
    @builds ||= begin
      command = safeguard_command [
        # find the site directories
        "find", partition_dir,
        "-mindepth", "5",
        "-maxdepth", "5",
        # only return files older than 1 hour:
        "-mmin", "+60",
        # look for directories only
        "-type", "d"
      ]

      GitHub.dogstats.distribution_time("pages.gc.find.dist", tags: ["partition:#{partition}"]) do
        IO.popen(command, "r") do |find|
          find.each_line.map do |path|
            Build.new(path.chomp) if GitHub::Routing.dpages_storage_path?(path.chomp)
          end.compact
        end
      end
    end
  end

  def delete_empty_folders
    GitHub.dogstats.distribution_time("pages.gc.delete_empty_folders.dist", tags: ["partition:#{partition}"]) do
      Progeny::Command.new(*(safeguard_command [
          # lookup inside partition dir
          "find", partition_dir,
          # stop one level below partition dir
          "-mindepth", "1",
          # start one level above site folders
          "-maxdepth", "4",
          # delete empty folders, older than 60 minutes
          "-mmin", "+60",
          "-type", "d",
          "-empty",
          # implies -depth so deletes in depth-first order
          "-delete"
        ]))
    end
  end

  def rm_rf(path)
    Progeny::Command.new(*rm_rf_command, path)
  end

  def rm_rf_command
    @rm_rf_command ||= begin
      safeguard_command ["rm", "-rf", "--"]
    end
  end

  def command_exist?(command)
    ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
      executable_filename = File.join(path, command)
      return true if test("f", executable_filename) && test("x", executable_filename)
    end

    false
  end

  # Prefix a command (passed as an array) with safeguards:
  # - nice, to reduce process priority
  # - ionice, to reduce process IO prioritoy
  # - timeout, stop the process after 58 minutes (kill it if unresponsive 2 minutes later) - max timeout = 60 minutes
  def safeguard_command(command, timeout = 58 * 60, kill_after = 2 * 60)
    if command_exist?("nice")
      # give the process lowest priority
      command = ["nice", "-n", "19", *command]
    end

    if command_exist?("ionice")
      # make I/O class 'idle'
      command = ["ionice", "-c", "3", *command]
    end

    if command_exist?("timeout")
      # timeout
      command = ["timeout", "--kill-after=#{kill_after}", "#{timeout}", *command]
    end

    command
  end

  def enabled?
    GitHub.flipper[:pages_gc].enabled?(GitHub::FlipperHost.local_host) || GitHub.enterprise?
  end

  def partition
    @partition ||= begin
      hour = Time.now.utc.hour
      hour % GitHub::Routing::DPAGES_PARTITIONS_COUNT
    end
  end

  def partition_dir
    @partition_dir ||= begin
      File.join(GitHub.pages_dir, partition.to_s)
    end
  end
end
