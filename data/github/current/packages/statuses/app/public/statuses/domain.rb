# typed: strict
# frozen_string_literal: true

module Statuses
  class Domain < GH::Domain::Base
    # Define a Enum to restrict group_by values.
    class GroupByField < T::Enum
      enums do
        SHA = new("sha")
        CONTEXT = new("context")
        STATE = new("state")
      end
    end

    # Get the Commit Status for the given ID in the repository.
    #
    # @param id The ID of the Status to get.
    # @param repository_id The Repository ID to scope to.
    # @return The Status for the given ID in the repository.
    sig { params(id: Integer, repository_id: Integer).returns(T.nilable(Status)).checked(:always).on_failure(:raise) }
    def for_id(id, repository_id:)
      ActiveRecord::Base.connected_to(role: :reading) do
        Status.find_by(id:, repository_id:)
      end
    end

    # Given a repository ID, returns true if there are any statuses for that repository.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @return [Boolean] True if there are statuses for the repository, false otherwise.
    sig { params(repository_id: T.nilable(Integer)).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def repository_has_statuses?(repository_id:)
      return false if repository_id.nil?
      Status.exists?(repository_id: repository_id)
    end

    # Check if a status check already exists for the given repository, SHA, and context.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param sha [String] The commit SHA to check for statuses.
    # @param context [String] The context to check for statuses.
    # @return [Boolean] True if a status check already exists, false otherwise.
    sig { params(repository_id: T.nilable(Integer), sha: String, context: String).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def status_exists?(repository_id:, sha:, context:)
      return false if repository_id.nil?

      ActiveRecord::Base.connected_to(role: :reading) do
        Status.exists?(repository_id: repository_id, sha: sha, context: context)
      end
    end

    # Given a repository ID and a list of SHAs, returns the current statuses for those SHAs.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param shas [Array<String>, nil] The SHAs to check for statuses.
    # @return [Array<Status>, nil] The current statuses for the given SHAs.
    sig { params(repository_id: T.nilable(Integer), shas: T::Array[String]).returns(T::Array[Status]).checked(:always).on_failure(:raise) }
    def current_statuses_for_shas(repository_id:, shas:)
      current_statuses_for_shas_relation(repository_id: repository_id, shas: shas).to_a
    end

    # [Deprecated] Given a repository ID and a list of SHAs, returns the current statuses for those SHAs, grouped by SHA.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param shas [Array<String>, nil] The SHAs to check for statuses.
    # @return [Hash<String, Array<Status>>, nil] The current statuses for the given SHAs, grouped by SHA.
    sig { params(repository_id: T.nilable(Integer), shas: T::Array[String]).returns(T::Hash[String, T::Array[Status]]).checked(:always).on_failure(:raise) }
    def current_statuses_for_shas_group_by_sha(repository_id:, shas:)
      return {} if shas.empty? || repository_id.nil?

      statuses = current_statuses_for_shas(repository_id: repository_id, shas: shas)
      statuses.group_by(&:sha)
    end

    # Given a repository ID and a list of SHAs, returns the current statuses for those SHAs, grouped by the given field.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param shas [Array<String>, nil] The SHAs to check for statuses.
    # @param group_by [Symbol] The field to group the statuses by.
    # @return [Hash<String, Array<Status>>, nil] The current statuses for the given SHAs, grouped by the given field.
    sig { params(repository_id: T.nilable(Integer), shas: T::Array[String], group_by: GroupByField).returns(T::Hash[String, T::Array[Status]]).checked(:always).on_failure(:raise) }
    def current_statuses_for_shas_group_by(repository_id:, shas:, group_by:)
      return {} if shas.empty? || repository_id.nil?

      statuses = current_statuses_for_shas_relation(repository_id: repository_id, shas: shas)
      # In memory operation without using dynamic public_send.
      statuses.group_by do |status|
        case group_by
        when GroupByField::SHA
          status.sha
        when GroupByField::CONTEXT
          status.context
        when GroupByField::STATE
          status.state
        end
      end
    end

    # Given a repository ID and a SHA, returns the most recent statuses for that SHA.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param sha [String, nil] The SHA to check for statuses.
    # @param pagination [GH::Pagination::Base] The pagination options.
    # @return [GH::Domain::Collection<Status>] The statuses for the given SHA.
    sig { params(repository_id: T.nilable(Integer), sha: T.nilable(String), pagination: GH::Pagination::Base).returns(GH::Domain::Collection[Status]).checked(:always).on_failure(:raise) }
    def list_for_sha(repository_id:, sha:, pagination:)
      ActiveRecord::Base.connected_to(role: :reading) do
        relation = Status.where(repository_id: repository_id, sha: sha).order(id: :desc)

        results = GH::Pagination::Paginator.paginate(scope: relation, pagination: pagination)
      end
    end

    # Given a repository ID and a SHA, returns all the statuses sorted in descending order
    # Currently unbounded but once https://github.com/github/actions-sudo/issues/913 is rolled out there will be a maximum of 5k statuses per SHA.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param sha [String, nil] The SHA to check for statuses.
    # @return [Array<Status>] The statuses for the given SHA.
    sig { params(repository_id: T.nilable(Integer), sha: T.nilable(String)).returns(T::Array[Status]).checked(:always).on_failure(:raise) }
    def list_all_for_sha(repository_id:, sha:)
      ActiveRecord::Base.connected_to(role: :reading) do
        Status.where(repository_id: repository_id, sha: sha).order(id: :desc).to_a
      end
    end

    # Prefetch the data for the given properties on the Statuses.
    # @param statuses The Statuses to prefetch.
    # @param properties The properties to prefetch.
    # @return The Statuses with their data prefetched.
    sig do
      type_parameters(:CollectionType).
      params(statuses: T.all(T::Enumerable[Status], T.type_parameter(:CollectionType)), properties: T::Array[Symbol]).
      returns(T.all(T::Enumerable[Status], T.type_parameter(:CollectionType))).
      checked(:always).
      on_failure(:raise)
    end
    def prefetch(statuses, properties)
      GitHub::PrefillAssociations.prefill_associations(statuses, properties)
      statuses
    end

    # Return the most recent statuses for a list of contexts and commit SHAs in a given repository.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param contexts [Array<String>, nil] The contexts to check for statuses.
    # @param shas [Array<String>, nil] The SHAs to check for statuses.
    # @return [Array<Status>, nil] The most recent statuses for the given contexts and SHAs.
    sig { params(repository_id: T.nilable(Integer), contexts: T::Array[String], shas: T::Array[String]).returns(T::Array[Status]).checked(:always).on_failure(:raise) }
    def current_statuses_for_contexts_and_shas(repository_id:, contexts:, shas:)
      return [] if shas.empty? || repository_id.nil?
      valid_contexts = contexts.select { |context| GitHub::UTF8.valid_unicode3?(context) }
      return [] if valid_contexts.empty?
      # This builds (but does not execute) a query to fetch the latest status ids for the given contexts and commit oids
      current_ids = Status.from("#{Status.table_name} FORCE INDEX (index_statuses_on_repository_id_and_sha_and_context)")
        .where(repository_id: repository_id, sha: shas, context: valid_contexts)
        .group(:sha, :context)
        .select("max(`id`)")

      # Here, we embed the subquery we build above, but we want to make sure that the subquery
      # is executed before the outer query is. If the outer query is executed first, MySQL loads
      # _all_ statuses for the given `repository_id`, which does not perform well at all.
      # We employ a "double nesting" trick that forces the subquery to be materialized first.
      Status.where(repository_id: repository_id).where(id: Status.from(current_ids).select("*")).to_a
    end

    # Create a new status
    # @param repository [Repository, nil] The repository to create the status for.
    # @param sha [String, nil] The commit SHA.
    # @param state [String, nil] The state of the status (success, pending, failure, error, expected).
    # @param user [User, nil] The user to create the status for.
    # @param context [String, nil] The context for the status.
    # @param oauth_application_id [Integer, nil] The ID of the OAuth application that created the status (optional).
    # @param target_url [String, nil] The target URL for the status (optional).
    # @param description [String, nil] The description of the status (optional).
    # @return [GH::Result<Status>] The created status, or an error.
    sig { params(repository: T.nilable(Repository), sha: T.nilable(String), state: T.nilable(String), user: T.nilable(User), context: T.nilable(String), oauth_application_id: T.nilable(Integer), target_url: T.nilable(String), description: T.nilable(String)).returns(GH::Result[Status]).checked(:always).on_failure(:raise) }
    def create(repository: nil, sha: nil, state: nil, user: nil, context: nil, oauth_application_id: nil, target_url: nil, description: nil)
      # TODO: Repository, sha, state, and user are required. We should raise an error if they are not provided.
      # We are allowing them to be nil for now to avoid breaking changes to the API. And allow ActiveRecord to raise
      # an error if they are not provided.
      ActiveRecord::Base.connected_to(role: :writing) do
        # Create a hash of the attributes and compact it to remove any nil values. This is necessary because the
        # `create!` method does not accept nil values for optional attributes. Specifically the `context` attribute
        # is optional but the model does not allow nil values. This is a workaround for that limitation until we can fix
        # the model to allow nil values for optional attributes. Related issue: https://github.com/github/github/pull/36781
        status = Status.create!({ repository: repository, sha: sha, state: state, creator: user, context: context, oauth_application_id: oauth_application_id, target_url: target_url, description: description }.compact)
        GitHub.dogstats.increment("domain.statuses.create", tags: ["result:ok"])
        GH::Result::Ok.new(status)
      end

    rescue ActiveRecord::RecordInvalid => error
      GitHub.dogstats.increment("domain.statuses.create", tags: ["result:error"])
      GH::Result::Error.new(error.message)
    end

    # Given a repository ID, a SHA, and a timestamp, returns the statuses for that SHA that were created before a given timestamp.
    # @param repository_id [Integer] The repository ID to check for statuses.
    # @param sha [String] The SHA to check for statuses.
    # @param timestamp [Time] The timestamp to check for statuses.
    # @return [Array<Status>] The statuses for the given SHA that were created before the given timestamp.
    sig { params(repository_id: T.nilable(Integer), sha: String, timestamp: Time).returns(T::Array[Status]).checked(:always).on_failure(:raise) }
    def statuses_created_before_timestamp(repository_id:, sha:, timestamp:)
      return [] if repository_id.nil?

      subquery = Status.from("#{Status.table_name} FORCE INDEX (index_statuses_on_repository_id_and_sha_and_context)")
        .where(repository_id: repository_id, sha: sha)
        .where("created_at < :timestamp", timestamp: timestamp)
        .group(:sha, :context)
        .select("max(`id`)")

      # Here, we embed the subquery we build above, but we want to make sure that the subquery
      # is executed before the outer query is. If the outer query is executed first, MySQL loads
      # _all_ statuses for the given `repository_id`, which does not perform well at all.
      # We employ a "double nesting" trick that forces the subquery to be materialized first.
      Status.where(repository_id: repository_id).where(id: Status.from(subquery).select("*")).order(id: :desc).to_a
    end

    # Returns a mapping of status contexts to their associated integrations for statuses created after a given timestamp.
    # Only returns up to the specified limit of most recent statuses.
    # @param repository_id [Integer] The repository ID to check for statuses.
    # @param start [Time] Only include statuses created after this time.
    # @param limit [Integer] Maximum number of recent statuses to check.
    # @return [Hash<String, Set<Integration>>] A hash mapping status contexts to sets of integrations.
    sig { params(repository_id: Integer, start: Time, limit: Integer).returns(T::Hash[String, T::Set[Integration]]).checked(:always).on_failure(:raise) }
    def recent_status_contexts_and_integrations(repository_id:, start:, limit:)
      sql = Arel.sql <<-SQL, repository_id: repository_id, start: start, limit: Arel.sql(limit.to_s)
        SELECT context, creator_id
        FROM statuses
        WHERE created_at > :start
        AND repository_id = :repository_id
        ORDER BY created_at DESC
        LIMIT :limit
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

    # Given a repository ID and a list of SHAs, returns the distinct SHAs from the statuses for those SHAs.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param shas [Array<String>, nil] The SHAs to check for statuses.
    # @return [Array<String>] The distinct SHAs from the statuses for the given SHAs.
    sig { params(repository_id: T.nilable(Integer), shas: T::Array[String]).returns(T::Array[String]) }
    def fetch_distinct_shas_from_statuses(repository_id:, shas:)
      return [] if repository_id.nil? || shas.empty?

      Status.from("#{Status.table_name} FORCE INDEX(index_statuses_on_repository_id_and_sha_and_context)")
        .where(repository_id: repository_id, sha: shas)
        .distinct
        .pluck(:sha)
    end

    # Given a start and end time, fetches the IDs of statuses that can be archived. For use in the archiving process.
    # @param updated_at_start [Time] The start time for the updated_at range.
    # @param updated_at_end [Time] The end time for the updated_at range.
    # @param archive_threshold_days [Time] The number of days to use as the threshold for archiving.
    # @param limit [Integer] The maximum number of statuses to return.
    # @return [Array<Array<Integer>>] The IDs of statuses that can be archived, grouped by repository ID and status ID.
    sig { params(updated_at_start: Time, updated_at_end: Time, archive_threshold_days: Time, limit: Integer).returns(T::Array[T::Array[Integer]]) }
    def archive_fetch_archivable_statuses(updated_at_start:, updated_at_end:, archive_threshold_days:, limit:)
      # Read from replicas when fetching the IDs to archive
      # index_statuses_on_is_archived_updated_at is a very good index since the sorted primary key is always appended to the end of secondary indexes so it's more like index_statuses_on_is_archived_updated_at_and_id
      ActiveRecord::Base.connected_to(role: :reading) do
        Status.from("#{Status.table_name} FORCE INDEX(index_statuses_on_is_archived_updated_at)")
          .where("is_archived = false")
          .where("updated_at between :updated_at_start AND :updated_at_end", updated_at_start: updated_at_start, updated_at_end: updated_at_end)
          .where("updated_at <= :updated_at", updated_at: archive_threshold_days)
          .order(id: :asc)
          .limit(limit)
          .pluck(:repository_id, :id)
      end
    end

    # Given a previous batch end time and an offset, fetches the updated_at range for archivable statuses. For use in the archiving process.
    # @param archive_threshold_days [Time] The number of days to use as the threshold for archiving.
    # @param previous_batch_end [Time, nil] The end time of the previous batch.
    # @param offset [Integer] The offset for the query.
    # @return [Array<Time, Time>, nil] The start and end times for the updated_at range.
    sig { params(archive_threshold_days: Time, previous_batch_end: T.nilable(Time), offset: Integer).returns(T.nilable(T::Array[Time])) }
    def archive_fetch_updated_at_range(archive_threshold_days:, previous_batch_end: nil, offset: 0)
      base_query = Status.from("#{Status.table_name} FORCE INDEX(index_statuses_on_is_archived_updated_at)")
        .where("is_archived = false")
        .where("updated_at <= ?", archive_threshold_days)
        .order("updated_at ASC")

      if previous_batch_end.present?
        base_query = base_query.where("updated_at > ?", previous_batch_end)
      end

      start_result = base_query.limit(1).pluck(:updated_at, :id)
      return nil unless start_result.present?

      updated_at_start = start_result[0].first

      if previous_batch_end.nil?
        archive_start_id = start_result[0].last
        GitHub.dogstats.count("checks.orchestrate_status_archiving.start_id", archive_start_id)
      end

      end_result = base_query.limit(1).offset(offset).pluck(:updated_at)

      if end_result.present?
        [updated_at_start, end_result.first]
      else
        [updated_at_start, updated_at_start]
      end
    end

    # Given a repository ID, returns statuses for export with optional filtering.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param filter_shas [Array<String>, nil] Optional list of SHAs to filter statuses to (e.g., PR head SHAs)
    # @param limit [Integer, nil] Optional limit on number of results to return
    # @param offset [Integer, nil] Optional offset for pagination
    # @return [Array<Status>] The statuses for export from the repository.
    sig { params(repository_id: T.nilable(Integer), filter_shas: T.nilable(T::Array[String]), limit: T.nilable(Integer), offset: T.nilable(Integer)).returns(T::Array[Status]).checked(:always).on_failure(:raise) }
    def list_for_export(repository_id:, filter_shas: nil, limit: nil, offset: nil)
      ActiveRecord::Base.connected_to(role: :reading) do
        build_export_relation(repository_id: repository_id, filter_shas: filter_shas)
          .order(id: :desc)
          .limit(limit)
          .offset(offset)
          .to_a
      end
    end

    # Given a repository ID, returns the total count of statuses for export with optional filtering.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param filter_shas [Array<String>, nil] Optional list of SHAs to filter statuses to (e.g., PR head SHAs)
    # @return [Integer] The total count of statuses for export from the repository.
    sig { params(repository_id: T.nilable(Integer), filter_shas: T.nilable(T::Array[String])).returns(Integer).checked(:always).on_failure(:raise) }
    def count_for_export(repository_id:, filter_shas: nil)
      ActiveRecord::Base.connected_to(role: :reading) do
        build_export_relation(repository_id: repository_id, filter_shas: filter_shas).count
      end
    end

    # Given a repository ID and an array of status attributes hashes, creates multiple status checks in a batch.
    # This method is optimized for large-scale imports and uses raw SQL for performance with Vitess sharding.
    # @param repository_id [Integer] The repository ID where the statuses will be created.
    # @param status_attributes [Array<Hash>] Array of status attribute hashes. Each hash should contain:
    #   - sha [String] The commit SHA
    #   - state [String] The status state (success, failure, pending, error)
    #   - context [String] The status context
    #   - creator [User] The user creating the status
    #   - description [String, nil] Optional description
    #   - target_url [String, nil] Optional target URL
    #   - oauth_application_id [Integer, nil] Optional OAuth application ID
    # @param batch_size [Integer] Optional batch size for insertion (default: 100)
    # @return [Integer] Number of status checks created
    # @raise [ArgumentError] When required parameters are missing or invalid
    # @raise [ActiveRecord::RecordInvalid] When validation fails
    sig { params(repository_id: Integer, status_attributes: T::Array[T::Hash[Symbol, T.untyped]], batch_size: Integer).returns(Integer).checked(:always).on_failure(:raise) }
    def batch_import(repository_id:, status_attributes:, batch_size: 100)
      raise ArgumentError, "No status attributes provided" if status_attributes.empty?

      total_created = 0

      ActiveRecord::Base.connected_to(role: :writing) do
        now = Time.current

        status_attributes.each_slice(batch_size) do |batch|
          # Validate and prepare values for batch insertion
          values = []

          batch.each do |attrs|
            # Validate required fields
            if attrs[:sha].nil? || attrs[:sha].empty?
              raise ArgumentError, "sha is required for status creation"
            end
            if attrs[:state].nil? || attrs[:state].empty?
              raise ArgumentError, "state is required for status creation"
            end
            if attrs[:context].nil? || attrs[:context].empty?
              raise ArgumentError, "context is required for status creation"
            end
            if attrs[:creator].nil?
              raise ArgumentError, "creator is required for status creation"
            end

            # Build the values array for insertion
            values << [
              repository_id,                      # repository_id
              attrs[:sha],                        # sha
              attrs[:state],                      # state
              attrs[:context],                    # context
              attrs[:creator].id,                 # creator_id
              attrs[:description],                # description
              attrs[:target_url],                 # target_url
              attrs[:oauth_application_id],       # oauth_application_id
              now,                                # created_at
              now                                 # updated_at
            ]
          end

          # Use raw SQL for bulk insertion that works with Vitess sharding
          sql_bindings = {
            values: Arel::Nodes::ValuesList.new(values)
          }

          sql = Arel.sql <<-SQL, **sql_bindings
            INSERT INTO `statuses`
              (`repository_id`, `sha`, `state`, `context`, `creator_id`,
               `description`, `target_url`, `oauth_application_id`, `created_at`, `updated_at`)
            :values
          SQL

          # Execute the bulk insert
          Status.connection.insert(sql)
          total_created += batch.length
        end
      end

      total_created
    rescue => error # rubocop:disable Style/RescueStandardError, Lint/GenericRescue
      raise error
    end

    private

    # [Private] Build the base relation for export methods with optional SHA filtering.
    # @param repository_id [Integer, nil] The repository ID to filter by.
    # @param filter_shas [Array<String>, nil] Optional list of SHAs to filter to.
    # @return [ActiveRecord::Relation<Status>] The base relation for export queries.
    sig { params(repository_id: T.nilable(Integer), filter_shas: T.nilable(T::Array[String])).returns(ActiveRecord::Relation).checked(:always).on_failure(:raise) }
    def build_export_relation(repository_id:, filter_shas:)
      relation = Status.where(repository_id: repository_id)
      return relation.none if filter_shas == []
      return relation.where(sha: filter_shas) if filter_shas
      relation
    end

    # [Private] Given a repository ID and a list of SHAs, returns an ActiveRecord::Relation.
    # @param repository_id [Integer, nil] The repository ID to check for statuses.
    # @param shas [Array<String>, nil] The SHAs to check for statuses.
    # @return [ActiveRecord::Relation<Status>, nil] The current statuses for the given SHAs.
    sig { params(repository_id: T.nilable(Integer), shas: T::Array[String]).returns(ActiveRecord::Relation).checked(:always).on_failure(:raise) }
    def current_statuses_for_shas_relation(repository_id:, shas:)
      return Status.none if shas.empty? || repository_id.nil?

      subquery = Status.from("#{Status.table_name} FORCE INDEX(index_statuses_on_repository_id_and_sha_and_context)")
        .where(repository_id: repository_id, sha: shas)
        .group(:sha, :context)
        .select("MAX(`id`)")

      # Here, we embed the subquery we built above, but we want to make sure that the subquery
      # is executed before the outer query is. If the outer query is executed first, MySQL loads
      # _all_ statuses for the given `repository_id`, which does not perform well at all.
      # We employ a "double nesting" trick that forces the subquery to be materialized first.
      Status.where(repository_id: repository_id).where(id: Status.from(subquery).select("*")).order(:id)
    end
  end
end
