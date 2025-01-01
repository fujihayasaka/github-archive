# typed: true
# frozen_string_literal: true

require "github/slice_query"

module GitHub::Backups::Maintenance
  include SliceQuery
  extend self

  def query_namespace
    "backups"
  end

  class CompareChecksumsError < StandardError; end

  def run_sweeper_ng
    measure_sweep_trace "repository" do
      find_repositories_ng.each do |(repository_id, _)|
        RepositoryBackupNgBackfillJob.perform_later(repository_id, :repository)
      end
    end

    measure_sweep_trace "wiki" do
      find_repository_wikis_ng.each do |(repository_id, _)|
        RepositoryBackupNgBackfillJob.perform_later(repository_id, :wiki)
      end
    end

    measure_sweep_trace "gist" do
      find_gists_ng.each do |(gist_id, _)|
        RepositoryBackupNgBackfillJob.perform_later(gist_id, :gist)
      end
    end
  end

  # Utility function to instrument the sweep segments
  def measure_sweep_trace(repo_type)
    GitHub.dogstats.time("gitbackups.sweep", tags: ["repo_type:#{repo_type}"]) do
      GitHub.tracer.in_span "find #{repo_type}", kind: :internal do |span|
        yield span
      end
    end
  end

  def find_from_table(table, prefix = "backup", domain_class, &block)
    slice_name = "#{prefix}-maintenance-#{table}"

    start_time, offset, slices = get_query_slice(slice_name)
    offset, next_offset = get_contiguous_id_range(table, domain_class, offset, slices)
    if rate_limited?(table, offset)
      return []
    end

    results = block_with_timeout(slice_name) do
      ActiveRecord::Base.connected_to(role: :reading) do
        block.call(offset, next_offset)
      end
    end

    if results.nil?
      return []
    end

    put_adjusted_query_slice(slice_name, start_time, offset, next_offset, slices)

    results
  end

  # Talks to compare-checksums-range and returns a list of repositories which
  # are out of date. Raises on error.
  def out_of_date(kind, checksums, with_networks, offset, next_offset, skip_if_broken_network, use_networks)
    compare = lambda do |_pid, stdin, stdout, _stderr|
      # We write in its own thread so it can block if stdin ever becomes full.
      write_thread = Thread.new do # rubocop:disable GitHub/ThreadUse
        checksums.each do |repository_id, checksum|
          network_id, broken = with_networks[repository_id]
          next if network_id.nil?
          # A wiki can still be fine if the network is broken as they don't share storage
          next if broken && skip_if_broken_network

          if use_networks
            stdin.puts JSON.fast_generate({ spec: "#{network_id}/#{repository_id}", checksum: checksum })
          else
            stdin.puts JSON.fast_generate({ repository_id: repository_id, checksum: checksum })
          end
        end
        stdin.close
      end

      # Read from stdout and parse each line as its own object. This can also be
      # made blocking as we only do so when stdout is empty and we just have to
      # wait for more output or the program closing the descriptor.
      ood = []
      begin
        stdout.each_line do |line|
          datum = JSON.parse(line)
          if use_networks
            network_id, repository_id = datum["spec"].split("/")
            ood << repository_id.to_i
          else
            ood << datum["repository_id"]
          end
        end
      rescue IOError
        # raised when the child process closes its stdout, we're done
        stdout.close
      end
      write_thread.join

      ood
    end

    GitHub::Backups.with_compare_checksums_range(kind, offset, next_offset, compare)
  end

  def get_outdated_repositories(offset, next_offset)
    checksums = GitHub::Backups.spokes_checksums_for_range(offset, next_offset, GitHub::DGit::RepoType::REPO)
    with_networks = GitHub::Backups.repository_networks(offset, next_offset)

    kind, use_networks =
    if GitHub.flipper[:gitbackups_use_networks].enabled?
      ["networks-and-repositories", true]
    else
      ["repositories", false]
    end

    out_of_date(kind, checksums, with_networks, offset, next_offset, true, use_networks)
  end

  def get_outdated_wikis(offset, next_offset)
    checksums = GitHub::Backups.spokes_checksums_for_range(offset, next_offset, GitHub::DGit::RepoType::WIKI)
    with_networks = GitHub::Backups.repository_networks(offset, next_offset)
    with_wikis = GitHub::Backups.repositories_with_wikis(offset, next_offset)

    # We don't always sync up the data perfectly, so 'checksums' might have
    # entries which aren't actually wikis anymore. Use 'with_wikis' to filter
    # down only to those which the app agrees are wikis which currently exist.
    filtered_checksums = checksums.select do |k, _v|
      with_wikis.include? k
    end

    kind, use_networks =
    if GitHub.flipper[:gitbackups_use_networks].enabled?
      ["networks-and-wikis", true]
    else
      ["wikis", false]
    end

    out_of_date(kind, filtered_checksums, with_networks, offset, next_offset, false, use_networks)
  end

  def get_outdated_gists(offset, next_offset)
    checksums = GitHub::Backups.spokes_checksums_for_range(offset, next_offset, GitHub::DGit::RepoType::GIST)
    with_names = GitHub::Backups.gist_reponames(offset, next_offset)

    res = []
    checksums.each_slice(100) do |slice|
      combined = []
      slice.each do |gist_id, checksum|
        reponame, broken = with_names[gist_id]
        next if reponame.nil?
        next if broken
        combined << { spec: "gist/#{reponame}", checksum: checksum }
      end

      return [] if combined.empty?

      # These are all gists, so they are in the form "gist/reponame"
      # TODO: Remember to clean up tests when removing this experiment
      gitbackups_res = science "gitbackups.vitess" do |e|
        e.use { GitHub::Backups.compare_checksums(combined) }
        e.try { GitHub::Backups.compare_checksums(combined, use_vitess: true) }
      end

      gitbackups_res.map do |spec|
        res << spec.split("/")[1]
      end
    end

    res
  end

  def find_repositories_ng
    find_from_table("repositories", "gitbackups", ApplicationRecord::Domain::Repositories) do |offset, next_offset|
      get_outdated_repositories(offset, next_offset)
    end
  end

  def find_repository_wikis_ng
    find_from_table("repositories", "gitbackups-wiki", ApplicationRecord::Domain::Repositories) do |offset, next_offset|
      get_outdated_wikis(offset, next_offset)
    end
  end

  def find_gists_ng
    find_from_table("gists", "gitbackups", ApplicationRecord::Domain::Gists) do |offset, next_offset|
      get_outdated_gists(offset, next_offset)
    end
  end
end
