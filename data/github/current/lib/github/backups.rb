# typed: false
# frozen_string_literal: true

module GitHub::Backups
  autoload :Maintenance, "github/backups/maintenance"

  class MaintenanceError < StandardError; end
  class FindRepositoriesError < StandardError; end
  class NeedMaintenanceError < StandardError; end
  class MarkScheduledError < StandardError; end
  class ExitError < StandardError; end
  class EnsureFreshKeyError < StandardError; end
  class WalMaintenanceError < StandardError; end
  class NeedMigrationError < StandardError; end

  def self.spawn_gitbackups(env, args)
    GitHub.tracer.in_span("git-backup", attributes: {
      "command" => args.first,
      "vitess" => env["GITBACKUPS_VITESS"].present?
    }, kind: :internal) do |_span|
      Progeny::Command.new(env, "/data/gitbackups/current/bin/git-backup", *args)
    end
  end

  def self.with_gitbackups(env, args, p)
    GitHub.tracer.in_span("git-backup", attributes: {
      "command" => args.first,
      "vitess" => env["GITBACKUPS_VITESS"].present?
    }, kind: :internal) do |_span|
      pid, stdin, stdout, stderr = Progeny::Command.spawn_with_pipes(env, "/data/gitbackups/current/bin/git-backup", *args)
      begin
        p.call(pid, stdin, stdout, stderr)
      ensure
        [stdin, stdout, stderr].each { |io| io.close unless io.closed? }
        _, status = Process::waitpid2(pid)
        raise ExitError unless status.exitstatus == 0
      end
    end
  end

  def self.compare_checksums(repos, use_vitess: false)
    as_json = JSON.dump(repos)

    env = {}
    env["GITBACKUPS_VITESS"] = "ro" if use_vitess

    output = spawn_gitbackups(env, ["compare-checksums", input: as_json])

    unless output.success?
      raise FindRepositoriesError
    end

    JSON.parse(output.out)
  end

  # Spawn compare-checksums-range and pass [pid, stdin, stdout, stderr] to the
  # lambda/proc p. The process is cleaned up after p returns.
  #
  # We use an explicit paremeter for the callback rather than a block due to the
  # stubbing/mocking constraints imposed by minitest and its handling of blocks.
  def self.with_compare_checksums_range(repo_type, offset, next_offset, p, use_vitess: false)
    env = {}
    env["GITBACKUPS_VITESS"] = "ro" if use_vitess

    with_gitbackups(env, ["compare-checksums-range", "--#{repo_type}", "--start", offset.to_s, "--end", next_offset.to_s], p)
  end

  def self.maintenance(spec, opts: {})
    scratch_dir = opts.key?(:scratch_dir) ? opts[:scratch_dir] : "/data/scratch"
    # The scheduler job takes care of specifying the network/wiki/gist in
    # the format accepted by the tool so we can simply pass it along.
    args = [
      "maintenance",
      "--scratch", scratch_dir,
      "--max-incrementals", "2000",
      "--gc-via-rpc",
      spec,
    ]

    output = spawn_gitbackups({}, args)

    unless output.success?
      raise MaintenanceError
    end
  end

  def self.need_maintenance(repo_type, max:, use_vitess: false)
    env = {}
    env["GITBACKUPS_VITESS"] = "ro" if use_vitess

    output = spawn_gitbackups(env, ["need-maintenance", "--max", max.to_s, "--#{repo_type}"])

    unless output.success?
      raise NeedMaintenanceError
    end

    JSON.parse(output.out)
  end

  def self.schedule_maintenance(to_schedule)
    GitHub::Gitbackups.client.schedule_maintenance(to_schedule)

    to_schedule.each do |spec|
      GitbackupsMaintenanceJob.perform_later(spec)
    end
  end

  def self.ensure_fresh_key
    output = spawn_gitbackups({}, ["ensure-fresh-key"])
    unless output.success?
      raise EnsureFreshKeyError
    end
  end

  def self.garbage_collect_wal(since)
    argv = [
      "garbage-collect-wal",
      "--since",
      since,
    ]

    output = spawn_gitbackups({}, argv)

    unless output.success?
      raise WalMaintenanceError
    end
  end

  # gets the network and repo id for +path+. e.g. given the input
  # "/data/repositories/d/nw/d9/7b/95/118148878/44415439.git", returns
  # ["118148878", "44415439"].  Note that both return values are strings; the
  # network portion may be "gist", for instance, and the repo portion may end in
  # ".wiki".
  def self.network_and_repo_id_for_path(path)
    network_id = File.basename(File.dirname(path))
    repo_id = File.basename(path, ".git")
    [network_id, repo_id]
  end

  # returns [reason, disabled_at] for the repository at +path+, or nil if the
  # repository's backups are not disabled, or if there's no matching repository.
  def self.backup_disabled_reason_for_path(path)
    network_id, repo_id = self.network_and_repo_id_for_path(path)

    results = nil
    ActiveRecord::Base.connected_to(role: :reading) do
      if network_id == "gist"
        sql = Arel.sql(<<-SQL, repository_id: repo_id)
        SELECT reason, disabled_at FROM gist_disabled_backups
        WHERE gist_repo_name = :repository_id
      SQL
      elsif repo_id.end_with?(".wiki")
        sql = Arel.sql(<<-SQL, repository_id: repo_id.sub(/\.wiki\z/, ""))
        SELECT reason, disabled_at FROM repository_wiki_disabled_backups
        WHERE repository_id = :repository_id
      SQL
      else
        sql = Arel.sql(<<-SQL, repository_id: repo_id)
        SELECT reason, disabled_at FROM repository_disabled_backups
        WHERE repository_id = :repository_id
      SQL
      end

      results = ApplicationRecord::Domain::GitbackupsMysql1.connection.select_rows(sql)
    end

    results.any? ? results[0] : nil
  end

  class RepositoryNotFound < StandardError; end

  # sets the disabled backup entry for the repository at +path+.
  def self.set_disabled_backups_entry_for_path(path, reason, time = nil)
    network_id, repo_id = self.network_and_repo_id_for_path(path)

    time = Time.now if !time

    if network_id == "gist"
      results = ApplicationRecord::Domain::Gists.connection.select_all(Arel.sql(<<-SQL, repo_name: repo_id))
        SELECT id FROM gists WHERE repo_name = :repo_name
      SQL

      raise RepositoryNotFound if !results.any?
      gist_id = results[0][0]

      ApplicationRecord::Domain::GitbackupsMysql1.connection.insert(Arel.sql(<<-SQL, gist_id: gist_id, repo_name: repo_id, reason: reason, disabled_at: time))
        REPLACE INTO gist_disabled_backups
          (gist_id, gist_repo_name, reason, disabled_at)
        VALUES
          (:gist_id, :repo_name, :reason, :disabled_at)
      SQL
    elsif repo_id.end_with?(".wiki")
      ApplicationRecord::Domain::GitbackupsMysql1.connection.insert(Arel.sql(<<-SQL, repository_id: repo_id.sub(/\.wiki\z/, ""), reason: reason, disabled_at: time))
        REPLACE INTO repository_wiki_disabled_backups
          (repository_id, reason, disabled_at)
        VALUES
          (:repository_id, :reason, :disabled_at)
      SQL
    else
      ApplicationRecord::Domain::GitbackupsMysql1.connection.insert(Arel.sql(<<-SQL, repository_id: repo_id, reason: reason, disabled_at: time))
        REPLACE INTO repository_disabled_backups
          (repository_id, reason, disabled_at)
        VALUES
          (:repository_id, :reason, :disabled_at)
      SQL
    end
  end

  # deletes the disabled backup entry for the repository at +path+. It's a no-op
  # if the repository doesn't exist, or isn't disabled.
  def self.delete_disabled_backups_entry_for_path(path)
    network_id, repo_id = self.network_and_repo_id_for_path(path)

    if network_id == "gist"
      ApplicationRecord::Domain::GitbackupsMysql1.connection.delete(Arel.sql(<<-SQL, gist_repo_name: repo_id))
        DELETE FROM gist_disabled_backups
        WHERE gist_repo_name = :gist_repo_name
      SQL
    elsif repo_id.end_with?(".wiki")
      ApplicationRecord::Domain::GitbackupsMysql1.connection.delete(Arel.sql(<<-SQL, repository_id: repo_id.sub(/\.wiki\z/, "")))
        DELETE FROM repository_wiki_disabled_backups
        WHERE repository_id = :repository_id
      SQL
    else
      ApplicationRecord::Domain::GitbackupsMysql1.connection.delete(Arel.sql(<<-SQL, repository_id: repo_id))
        DELETE FROM repository_disabled_backups
        WHERE repository_id = :repository_id
      SQL
    end
  end

  # gets the spokes checksum for the repository at +path+, if any.
  def self.spokes_checksum_for_path(path)
    network_id, repo_id = self.network_and_repo_id_for_path(path)

    results = ActiveRecord::Base.connected_to(role: :reading) do
      if network_id == "gist"
        results = ApplicationRecord::Domain::Gists.connection.select_all(Arel.sql(<<-SQL, repo_name: repo_id))
          SELECT id FROM gists WHERE repo_name = :repo_name
        SQL

        raise RepositoryNotFound if !results.any?
        gist_id = results[0][0]

        GitHub::DGit::DB.for_gist_id(gist_id).SQL.results(<<-SQL, gist_id: gist_id, gist_repo_type: GitHub::DGit::RepoType::GIST)
            SELECT checksum FROM repository_checksums
            WHERE
                repository_id = :gist_id
            AND repository_type = :gist_repo_type
          SQL
      elsif repo_id.end_with?(".wiki")
        GitHub::DGit::DB.for_network_id(network_id).SQL.results(<<-SQL, network_id: network_id, repository_id: repo_id.sub(/\.wiki\z/, ""), wiki_repo_type: GitHub::DGit::RepoType::WIKI)
            SELECT checksum FROM repository_checksums
            WHERE
                repository_id = :repository_id
            AND repository_type = :wiki_repo_type
          SQL
      else
        GitHub::DGit::DB.for_network_id(network_id).SQL.results(<<-SQL, network_id: network_id, repository_id: repo_id, repo_repo_type: GitHub::DGit::RepoType::REPO)
            SELECT checksum FROM repository_checksums
            WHERE
                repository_id = :repository_id
            AND repository_type = :repo_repo_type
          SQL
      end
    end

    results[0][0] if results.any?
  end

  def self.spokes_checksums_for_range(lower, upper, repo_type)
    result = {}
    dbs = repo_type == GitHub::DGit::RepoType::GIST ? GitHub::DGit::DB.each_gist_db : GitHub::DGit::DB.each_network_db

    if repo_type == GitHub::DGit::RepoType::WIKI && GitHub.flipper[:gitbackups_repo_checksums_use_index_hint_for_wikis].enabled?
      index_hint = "USE INDEX (index_repository_checksums_on_repository_type)"
    else
      index_hint = ""
    end

    dbs.each do |db|
      rows = db.SQL.results(<<-SQL, repo_type: repo_type, lower: lower, upper: upper, index_hint: index_hint)
               SELECT repository_id, checksum FROM repository_checksums #{index_hint}
                WHERE repository_type = :repo_type
                  AND repository_id > :lower AND repository_id <= :upper
             SQL
      result.update(Hash[rows])
    end # dbs.each

    result
  end

  def self.repositories_with_wikis(lower, upper)
    ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, lower: lower, upper: upper)).flatten
      SELECT repository_id FROM repository_wikis
      WHERE repository_id > :lower AND repository_id <= :upper
    SQL
  end

  def self.repository_networks(lower, upper)
    rows = ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, lower: lower, upper: upper))
      SELECT /*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ r.id, r.source_id,
        (r.disabling_reason = "broken" OR rn.maintenance_status = "broken")
        FROM repositories r
        JOIN repository_networks rn ON r.source_id=rn.id
       WHERE r.id > :lower AND r.id <= :upper
    SQL
    rows.map do |row|
      [row[0], [row[1], row[2] == 1]]
    end.to_h
  end

  def self.gist_reponames(lower, upper)
    rows = ApplicationRecord::Domain::Gists.connection.select_rows(Arel.sql(<<-SQL, lower: lower, upper: upper))
      SELECT id, repo_name, (maintenance_status = "broken")
        FROM gists
       WHERE id > :lower AND id <= :upper
    SQL
    rows.map do |row|
      [row[0], [row[1], row[2] == 1]]
    end.to_h
  end

  def self.need_migration(repo_type, max:)
    output = spawn_gitbackups({}, ["need-migration", "--max", max.to_s, "--#{repo_type}"])

    unless output.success?
      raise NeedMigrationError
    end

    JSON.parse(output.out)
  end

  def self.schedule_migration(to_schedule)
    GitHub::Gitbackups.client.schedule_maintenance(to_schedule)

    to_schedule.each do |spec|
      output = spawn_gitbackups({}, ["migrate-mode", "set", spec, "--s3", "optional", "--abs", "required"])
      if output.success?
        # only schedule maintenance if successfully enabled ABS storage for this repo
        GitHub::Logger.log(message: "scheduling maintenance for storage migration", spec: spec)
        if GitHub.flipper[:gitbackups_migration_dedicated_queue].enabled?
          GitbackupsMigrationJob.perform_later(spec, opts: { scratch_dir: "/data/repositories/gitbackups-scratch" })
        else
          GitbackupsMaintenanceJob.perform_later(spec)
        end
      else
        GitHub::Logger.log(message: "failed to update storage migration modes", spec: spec)
      end
    end
  end
end
