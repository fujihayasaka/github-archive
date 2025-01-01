# typed: true
# frozen_string_literal: true

module Statuses
  # this service provides an interface for all queries going to the statuses
  # table. As we are transitioning the statuses table out of mysql1 and into
  # the ballast cluster, we will use this service to encapsulate routing
  # logic and to trigger data transition jobs
  class Service

    # READS
    #
    # For those times when you want the status just prior to this one.
    # Returns a Status or nil.
    def self.previous_status(repo_id:, sha:, status_id:, context:)
      sql = Arel.sql <<-SQL, repo_id: repo_id, sha: sha, status_id: status_id, context: context
        SELECT *
        FROM statuses
        FORCE INDEX (index_statuses_on_repository_id_and_sha_and_context)
        WHERE repository_id = :repo_id
        AND sha = :sha
        AND context = :context
        AND id < :status_id
        ORDER BY id DESC
        LIMIT 1
        /*GitHub-StatusesService.previous_status*/
      SQL
      Status.find_by_sql(sql).first
    end

    def self.count_per_sha_and_context(repo_id:, sha:, context:)
      # context is a MySQL varchar so it only accepts UTF-8 characters
      # up to 3 bytes.
      return 0 unless GitHub::UTF8.valid_unicode3?(context)
      sql = Arel.sql <<-SQL, repo_id: repo_id, sha: sha, context: context
        SELECT COUNT(*)
        FROM statuses
        WHERE repository_id = :repo_id
        AND sha = :sha
        AND context = :context
        /*GitHub-StatusesService.count_per_sha_and_context*/
      SQL

      Status.connection.select_value(sql)
    end

    # Public: Return the most recent statuses for each context associated with the
    # given commit sha.
    #
    # repository - A Repository
    # sha        - A String or Array of one or more String SHAs to query.
    #              SHAs must be the full 40-character SHA.
    #
    # Example:
    #   Statuses::Service.current_for_shas(repository_id: repo.id, shas: "deadbeef...")
    #   #=> [#<Status context: 'blah' ...>, #<Status context: 'whatevs' ...>, #<Status context: default ... >]
    #
    # Returns an Array of Statuses.
    def self.current_for_shas(repository_id:, shas:)
      return [] if shas.empty?
      GitHub.dogstats.time("statuses_service", tags: ["action:current_for_shas"]) do
        # This builds (but does not execute) a query to fetch the latest status ids for all
        # contexts recorded for the given `sha` values
        current_ids = Status.from("#{Status.table_name} FORCE INDEX (index_statuses_on_repository_id_and_sha_and_context)").
          where(repository: repository_id, sha: Array(shas)).
          group(:sha, :context).
          select("max(`id`)")

        Status.where(repository_id: repository_id).
          # Here, we embed the subquery we build above, but we want to make sure that the subquery
          # is executed before the outer query is. If the outer query is executed first, MySQL loads
          # _all_ statuses for the given `repository_id`, which does not perform well at all.
          #
          # We employ a "double nesting" trick that forces the subquery to be materialized first.
          where(id: Status.from(current_ids).select("*")).
          order(:id).
          annotate("GitHub-StatusesService.current_for_shas")
      end
    end

    # Return the current statuses by sha for the given repository and shas
    #
    # repository - a Repository instance
    # shas       - an Array of String commit shas
    #
    # Returns a Hash of {"sha" => [ <Status>,  ... ], ... }
    def self.current_by_sha(repository_id:, shas:)
      shas = Array.wrap(shas)
      if shas.empty?
        {}
      else
        GitHub.dogstats.time("statuses_service", tags: ["action:current_by_sha"]) do
          res = current_for_shas(repository_id: repository_id, shas: shas)
          res.group_by(&:sha)
        end
      end
    end

    # Return the most recent Statuses for a list of contexts and commit_oids
    #
    # repository  - A Repository
    # contexts    - Array of String context names
    # commit_oids - Array of commit_oids for the Status records
    #
    # Returns an Array of Statuses
    def self.current_for(repo_id:, contexts:, commit_oids:, connection: Status.connection)
      # context is a MySQL varchar so it only accepts UTF-8 characters up to 3 bytes.
      valid_contexts = contexts.select { |context| GitHub::UTF8.valid_unicode3?(context) }
      return [] if valid_contexts.empty?

      # This builds (but does not execute) a query to fetch the latest status ids for the
      # given contexts and commit oids
      current_ids = Status.from("#{Status.table_name} FORCE INDEX (index_statuses_on_repository_id_and_sha_and_context)").
        where(repository: repo_id, sha: Array(commit_oids), context: valid_contexts).
        group(:sha, :context).
        select("max(`id`)")

      Status.where(repository_id: repo_id).
        # Here, we embed the subquery we build above, but we want to make sure that the subquery
        # is executed before the outer query is. If the outer query is executed first, MySQL loads
        # _all_ statuses for the given `repository_id`, which does not perform well at all.
        #
        # We employ a "double nesting" trick that forces the subquery to be materialized first.
        where(id: Status.from(current_ids).select("*")).
        annotate("GitHub-StatusesService.current_for")
    end

    # Retrieve Status contexts that have been posted to the repository
    # recently.
    #
    # Returns a Set of Strings.
    def self.recent_status_contexts(repo_id:, start:, limit:)
      GitHub.dogstats.time("protected_branch", tags: ["action:recent_status_contexts"]) do
        # If you change the timeframe here, be sure to update the user-visible
        # copy on the Protected Branch settings page.
        sql = Arel.sql <<-SQL, repo_id: repo_id, start: start, limit: limit
          SELECT DISTINCT context
          FROM statuses
          WHERE created_at > :start
          AND repository_id = :repo_id
          LIMIT :limit
          /*GitHub-StatusesService.recent_status_contexts*/
        SQL

        Status.connection.select_rows(sql).map(&:first).to_set
      end
    end

    # Retrieve Status contexts that have been posted to the repository
    # recently, and the Integrations that were used to create them.
    #
    # Returns a Hash of Sets of Strings.
    def self.recent_status_contexts_and_integrations(repo_id:, start:, limit:)
      GitHub.dogstats.time("protected_branch", tags: ["action:recent_status_contexts_and_integrations"]) do
        sql = Arel.sql <<-SQL, repo_id: repo_id, start: start, limit: Arel.sql(limit.to_s)
          SELECT context, creator_id
          FROM statuses
          WHERE created_at > :start
          AND repository_id = :repo_id
          ORDER BY created_at DESC
          LIMIT :limit
          /*GitHub-StatusesService.recent_status_contexts_and_integrations*/
        SQL

        results = Status.connection.select_rows(sql).uniq
        bot_ids = results.map { |_, bot_id| bot_id }
        integrations = Integration.includes(:bot).where(bot_id: bot_ids).group_by(&:bot_id)

        results.each_with_object({}) do |(context, bot_id), results|
          results[context] ||= Set.new
          if integrations.has_key?(bot_id)
            results[context].merge(integrations[bot_id])
          end
        end
      end
    end

    # Returns an array of statuses
    def self.statuses_at_merge(repository:, sha:, merged_at:)
      latest_status_ids_at_merge = Status.from("#{Status.table_name} FORCE INDEX (index_statuses_on_repository_id_and_sha_and_context)").
        where(repository: repository.id, sha: sha).
        where("created_at < :merged_at", merged_at: merged_at).
        group(:sha, :context).
        select("max(`id`)")

      Status.where(repository_id: repository.id).
        # Here, we embed the subquery we build above, but we want to make sure that the subquery
        # is executed before the outer query is. If the outer query is executed first, MySQL loads
        # _all_ statuses for the given `repository_id`, which does not perform well at all.
        #
        # We employ a "double nesting" trick that forces the subquery to be materialized first.
        where(id: Status.from(latest_status_ids_at_merge).select("*")).
        order(id: :desc).
        annotate("GitHub-StatusesService.statuses_at_merge")
    end

    def self.statuses_for_repo_exist?(repository_id:)
      sql = Arel.sql <<-SQL, repo_id: repository_id
        SELECT id
        FROM statuses
        WHERE repository_id = :repo_id
        LIMIT 1
        /*GitHub-StatusesService.statuses_for_repo_exist*/
      SQL
      Status.connection.select_value(sql).present?
    end

    # WRITES
    #
    # creates a status
    # called from the API
    #
    # Returns a tuple [Status record, ActiveRecord::RecordInvalid error or nil]
    def self.create_status(repo:, data:, user:)
      context_pieces = [data["context"]]
      data[:repository] = repo
      data[:creator] = user
      data[:context] = context_pieces.compact.join(" ") if context_pieces.any?

      Status.create!(data)
    rescue ActiveRecord::RecordInvalid => error
      [error.record, error]
    end

    PER_PAGE = 30

    # Look up statuses by repository ID and SHA, and paginate the results.
    #
    # Returns a WillPaginate::Collection.
    def self.paginated_statuses(repo_id:, sha:, per_page: PER_PAGE, page: 1)
      collection = WillPaginate::Collection.new(page, per_page)
      if repo_id.nil? || sha.nil?
        collection.total_entries = 0
        return collection
      end

      sql = Arel.sql <<~SQL, repo_id: repo_id, sha: sha, limit: Arel.sql(per_page.to_s), offset: Arel.sql(((page - 1) * per_page).to_s)
        SELECT `statuses`.* FROM `statuses`
        WHERE `statuses`.`repository_id` = :repo_id
          AND `statuses`.`sha` = :sha
        ORDER BY statuses.id DESC
        LIMIT :limit OFFSET :offset
      SQL

      collection.replace Status.find_by_sql(sql)

      if collection.total_entries.nil?
        count_sql = Arel.sql <<~SQL, repo_id: repo_id, sha: sha
          SELECT count(*) FROM `statuses`
          WHERE `statuses`.`repository_id` = :repo_id
            AND `statuses`.`sha` = :sha
        SQL
        collection.total_entries = Status.connection.select_value(count_sql)
      end

      collection
    end
  end
end
