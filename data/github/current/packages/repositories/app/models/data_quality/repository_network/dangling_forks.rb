# typed: false
# frozen_string_literal: true

require "github/sql/readonly"

module DataQuality::RepositoryNetwork
  class DanglingForks
    include GitHub::Telemetry::Logs::Loggable
    class Error < StandardError; end

    class Fork
      attr_reader :repository, :owner, :parent_repository

      def initialize(repository, owner, parent_repository)
        @repository = repository
        @owner = owner
        @parent_repository = parent_repository
      end

      def owner_id
        @owner.id
      end

      def parent_id
        @parent_repository.id
      end

      def repository_id
        repository.id
      end

      def ahead_of_parent?
        return false unless parent_repository&.default_branch_exists? && repository&.default_branch_exists?

        repository.comparison(parent_repository.default_oid, repository.default_oid).ahead?
      rescue GitRPC::ObjectMissing
        Failbot.report(Error.new("Comparison failed between #{repository.id}@#{repository.default_oid} and #{parent_repository.id}@#{parent_repository.default_oid}"))
        false
      end
    end

    def initialize(clean: false, start: nil, finish: nil)
      @start  = start || min_id
      @finish = finish || max_id
      @clean  = clean
      logger.info("Initializing", "code.namespace" => self.class.name)
    end

    def min_id
      @min_id ||= Repository.connection.select_value(Arel.sql("SELECT MIN(ID) FROM repositories")) || 0
    end

    def max_id
      @max_id ||= Repository.connection.select_value(Arel.sql("SELECT MAX(ID) FROM repositories")) || 0
    end

    def dangling_repo_batches
      @iterator ||=
        begin
          scope = Repository
            .joins("INNER JOIN `repositories` `parents` ON `parents`.`id` = `repositories`.`parent_id`")
            .distinct
            .where.not(parent_id: nil)
            .where(public: false)
            .where(parents: { public: false })
            .where(active: true)

          iter = GitHub::QueryBatching::ScopeIterator
            .new(scope, start: @start, finish: @finish, batch_size: 20)
            .pluck(:id, :owner_id, :parent_id, "parents.owner_id")

          GitHub::SQL::Readonly.new(iter.batches)
        end
    end

    def run
      removed_fork_ids = Set.new
      total_archived_forks = 0
      total_forks = 0
      could_not_be_deleted = []
      logger.info("Processing fork repo ids", "gh.forks.clean_dangling.start" => @start, "gh.forks.clean_dangling.finish" => @finish)

      dangling_repo_batches.each do |rows|
        Repository.throttle do
          owner_ids = rows.map(&:second)
          parent_owner_ids = rows.map(&:fourth)
          users_and_orgs = User.where(id: owner_ids + parent_owner_ids)
          user_owners = users_and_orgs.select { |owner| owner.user? }.index_by(&:id)
          org_owners = users_and_orgs.select { |owner| owner.organization? }.index_by(&:id)

          repository_ids = rows.flat_map { |r| [r[0], r[2]] }
          repositories = Repository.where(id: repository_ids).index_by(&:id)

          rows.each do |fork_id, fork_owner_id, parent_id, parent_owner_id|
            next if removed_fork_ids.include?(fork_id)
            GitHub.dogstats.increment("dangling_forks.forks_scanned")

            fork = repositories[fork_id]
            parent = repositories[parent_id]
            fork_owner_user = user_owners[fork_owner_id]
            fork_owner_org = org_owners[fork_owner_id]
            parent_owner_org = org_owners[parent_owner_id]
            parent_owner_user = user_owners[parent_owner_id]

            next if fork_owner_user.nil? # The fork is org-owned. We never remove org-owned forks.

            next if parent.nil? || parent.permit?(fork_owner_user, :read)

            removed_fork_ids << fork_id
            dangling_fork = Fork.new(fork, fork_owner_user, parent)

            # For use in DetectOutOfSyncForks transition
            yield dangling_fork if block_given? && !parent_owner_org.nil?

            total_forks += 1

            if clean?
              begin
                logger.info("Removing fork", "gh.fork.id" => fork_id, "gh.fork.owner_id" => fork_owner_id, "gh.fork.parent_id" => parent_id)
                dangling_fork.repository.remove(nil)
                GitHub.dogstats.increment("dangling_forks.forks_removed")
                total_archived_forks += 1
              rescue StandardError => e # rubocop:todo Lint/GenericRescue
                could_not_be_deleted << fork_id
                GitHub.dogstats.increment("dangling_forks.fork_removal_failures")
                Failbot.report(Error.new("Dangling fork archive died on fork ID: #{fork_id}. #{e.class}: #{e.full_message}"))
              end
            end
          end
        end
      end

      GitHub.instrument "data_quality.archive_dangling_forks", {
        host_name: GitHub.local_host_name,
        start_repo_id: @start,
        finish_repo_id: @finish,
        clean: clean?,
        total_forks_count: total_forks,
        archived_forks_count: total_archived_forks,
      }

      GitHub.dogstats.gauge("dangling_forks.max_repo_id_scanned", @finish)

      if clean? && could_not_be_deleted.any?
        logger.info("Could not delete forks", "gh.forks.dangling_fork_ids" => could_not_be_deleted)
      end
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      GitHub.dogstats.increment("dangling_forks.unhandled_exceptions")
      Failbot.report(Error.new("Unhandled exception scanning repos #{@start} to #{@finish}. #{e.class}: #{e.full_message}"))
      raise
    end

    def clean?
      @clean
    end
  end
end
