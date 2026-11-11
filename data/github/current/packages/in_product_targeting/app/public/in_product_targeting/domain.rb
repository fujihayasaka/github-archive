# typed: strict
# frozen_string_literal: true

module InProductTargeting
  class Domain < GH::Domain::Base

    MAX_BATCH_RECORDS = 500

    # Returns a metadata json object if there's a match or nil if not
    sig { params(user_id: T.nilable(Integer), organization_id: T.nilable(Integer), enterprise_id: T.nilable(Integer), repository_id: T.nilable(Integer), cohort: T.nilable(String), day: T.nilable(String)).returns(T.nilable(T::Hash[String, T.untyped])) }
    def match?(user_id: nil, organization_id: nil, enterprise_id: nil, repository_id: nil, cohort: nil, day: nil)
      return nil if GitHub.multi_tenant_enterprise? || GitHub.enterprise?

      if organization_id.present?
        ::IpmOrganizationMatch.find_by(organization_id: organization_id, cohort: cohort, day: day)&.metadata
      elsif enterprise_id.present?
        ::IpmEnterpriseMatch.find_by(enterprise_id: enterprise_id, cohort: cohort, day: day)&.metadata
      elsif repository_id.present?
        ::IpmRepositoryMatch.find_by(repository_id: repository_id, cohort: cohort, day: day)&.metadata
      else
        ::IpmMatch.find_by(user_id: user_id, cohort: cohort, day: day)&.metadata
      end
    end

    # Returns a mapping of days to their most recent metadata for the given entity and cohort
    sig { params(user_id: T.nilable(Integer), organization_id: T.nilable(Integer), enterprise_id: T.nilable(Integer), repository_id: T.nilable(Integer), cohort: T.nilable(String), start_day: T.nilable(String)).returns(T::Hash[String, T::Hash[String, T.untyped]]) }
    def matches_by_day(user_id: nil, organization_id: nil, enterprise_id: nil, repository_id: nil, cohort: nil, start_day: nil)
      return {} if GitHub.multi_tenant_enterprise? || GitHub.enterprise?
      return {} if cohort.nil?

      # Determine which model and column to use
      if organization_id.present?
        model = ::IpmOrganizationMatch
        id_column = :organization_id
        id_value = organization_id
        table_name = "ipm_organization_matches"
      elsif enterprise_id.present?
        model = ::IpmEnterpriseMatch
        id_column = :enterprise_id
        id_value = enterprise_id
        table_name = "ipm_enterprise_matches"
      elsif repository_id.present?
        model = ::IpmRepositoryMatch
        id_column = :repository_id
        id_value = repository_id
        table_name = "ipm_repository_matches"
      else
        return {} if user_id.nil?
        model = ::IpmMatch
        id_column = :user_id
        id_value = user_id
        table_name = "ipm_matches"
      end

      query = model.where(id_column => id_value, :cohort => cohort)

      # Add date filter only if start_day is provided
      query = query.where(day: start_day..) if start_day.present?

      # Group by day and get most recent records using a subquery
      query = query.joins(<<~SQL)
        INNER JOIN (
          SELECT day, MAX(updated_at) as max_updated_at
          FROM #{table_name}
          WHERE #{id_column} = '#{ActiveRecord::Base.sanitize_sql(id_value)}'
            AND cohort = '#{ActiveRecord::Base.sanitize_sql(query.where_values_hash["cohort"])}'
          GROUP BY day
        ) latest ON #{table_name}.day = latest.day AND #{table_name}.updated_at = latest.max_updated_at
      SQL

      query
        .index_by(&:day)
        .transform_values(&:metadata)
    end

    # Idempotent check-then-insert for a single match record.
    # If a match already exists for the given entity, cohort, and today's date,
    # this is a no-op. Otherwise, creates the match via bulk_create_matches.
    # The IPM tables have no unique index on (entity_id, cohort, day), so this
    # guard prevents duplicate rows.
    sig do
      params(
        cohort: String,
        user_id: T.nilable(Integer),
        organization_id: T.nilable(Integer),
        enterprise_id: T.nilable(Integer),
        metadata: T::Hash[String, T.untyped],
      ).void
    end
    def record_enabled(cohort:, user_id: nil, organization_id: nil, enterprise_id: nil, metadata: {})
      return if GitHub.multi_tenant_enterprise? || GitHub.enterprise?

      entity_ids = [user_id, organization_id, enterprise_id].compact
      raise ArgumentError, "exactly one of user_id, organization_id, or enterprise_id is required" if entity_ids.length != 1

      today = Time.current.to_date.to_s

      return if match?(
        user_id: user_id,
        organization_id: organization_id,
        enterprise_id: enterprise_id,
        cohort: cohort,
        day: today,
      )

      match_data = { cohort: cohort, day: today, metadata: metadata }
      match_data[:user_id] = user_id if user_id
      match_data[:organization_id] = organization_id if organization_id
      match_data[:enterprise_id] = enterprise_id if enterprise_id

      bulk_create_matches(matches: [match_data])
    end

    # Creates multiple IpmMatches in bulk with the provided attributes
    # Accepts matches with user_id, organization_id, or enterprise_id
    sig { params(matches: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
    def bulk_create_matches(matches:)
      return true if GitHub.multi_tenant_enterprise? || GitHub.enterprise?
      return true if matches.empty?

      GitHub.logger.info("Creating matches in bulk", {
        "in_product_targeting.matches_count" => matches.length
      })

      ActiveRecord::Base.connected_to(role: :writing) do
        # Group matches by type
        user_matches = []
        org_matches = []
        ent_matches = []
        repo_matches = []

        matches.each do |match|
          if match[:organization_id].present?
            org_matches << match
          elsif match[:enterprise_id].present?
            ent_matches << match
          elsif match[:repository_id].present?
            repo_matches << match
          else
            user_matches << match
          end
        end

        # Prepare data for bulk insert
        current_time = Time.current
        max_records = MAX_BATCH_RECORDS

        begin
          # Insert user matches
          if user_matches.any?
            user_records = map_matches_to_records("user", user_matches, current_time)
            if user_records.length > max_records
              max_records_exceeded("", user_records.length)
            end

            ::IpmMatch.insert_all(user_records)
          end

          # Insert organization matches
          if org_matches.any?
            org_records = map_matches_to_records("organization", org_matches, current_time)

            if org_records.length > max_records
              max_records_exceeded("organization", org_records.length)
            end

            ::IpmOrganizationMatch.insert_all(org_records)
          end

          # Insert enterprise matches
          if ent_matches.any?
            ent_records = map_matches_to_records("enterprise", ent_matches, current_time)
            if ent_records.length > max_records
              max_records_exceeded("enterprise", ent_records.length)
            end

            ::IpmEnterpriseMatch.insert_all(ent_records)
          end

          # Insert repository matches
          if repo_matches.any?
            repo_records = map_matches_to_records("repository", repo_matches, current_time)
            if repo_records.length > max_records
              max_records_exceeded("repository", repo_records.length)
            end

            ::IpmRepositoryMatch.insert_all(repo_records)
          end

          # Get total count
          count = user_matches.length + org_matches.length + ent_matches.length + repo_matches.length

          GitHub.logger.info("Successfully bulk created IpmMatches", {
            "in_product_targeting.created_count" => count
          })

          # Return true to indicate success instead of IDs
          true
        rescue ActiveRecord::RecordNotUnique => e
          GitHub.logger.error("Duplicate record error during bulk insert", {
            "in_product_targeting.error" => e.message
          })
          raise e
        end
      end
    end

    # Map array of match hashes to the format required for bulk insertion, adding timestamps
    sig { params(type: String, matches: T::Array[T::Hash[Symbol, T.untyped]], current_time: Time).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    private def map_matches_to_records(type, matches, current_time)
      matches.map do |match|
        {
         "#{type}_id": match[:"#{type}_id"],
          cohort: match[:cohort],
          day: match[:day],
          metadata: match[:metadata],
          created_at: current_time,
          updated_at: current_time
        }
      end
    end

    # max records error handler, takes type argument and integer as parameters
    sig { params(type: String, requested_count: Integer).void }
    private def max_records_exceeded(type, requested_count)
      max_records = MAX_BATCH_RECORDS
      error_message = "Bulk insert exceeds maximum allowed records (#{max_records})"
      GitHub.logger.error("Failed to bulk create Ipm#{type.capitalize}Matches", {
        "in_product_targeting.error" => error_message,
        "in_product_targeting.requested_count" => requested_count,
        "in_product_targeting.max_allowed" => max_records
      })
      raise ArgumentError, error_message
    end

    # Deletes all IpmMatches for a specific day and cohort across all entity types (users, organizations, enterprises).
    #
    # @param day [String] The day in ISO 8601 format (YYYY-MM-DD).
    # @param cohort [String] The cohort identifier.
    # @return [Integer] The total number of deleted matches across all tables.
    sig { params(day: String, cohort: String).returns(Integer) }
    def delete_matches_by_day_and_cohort(day:, cohort:)
      return 0 if GitHub.multi_tenant_enterprise? || GitHub.enterprise?

      GitHub.logger.info("Deleting matches", {
        "in_product_targeting.day" => day,
        "in_product_targeting.cohort" => cohort
      })

      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          # Delete from all three tables
          user_deleted = ::IpmMatch.where(day: day, cohort: cohort).delete_all
          org_deleted = ::IpmOrganizationMatch.where(day: day, cohort: cohort).delete_all
          ent_deleted = ::IpmEnterpriseMatch.where(day: day, cohort: cohort).delete_all
          repo_deleted = ::IpmRepositoryMatch.where(day: day, cohort: cohort).delete_all

          total_deleted = user_deleted + org_deleted + ent_deleted + repo_deleted

          GitHub.logger.info("Successfully deleted IpmMatches", {
            "in_product_targeting.deleted_count" => total_deleted,
            "in_product_targeting.user_deleted" => user_deleted,
            "in_product_targeting.org_deleted" => org_deleted,
            "in_product_targeting.ent_deleted" => ent_deleted,
            "in_product_targeting.repo_deleted" => repo_deleted,
            "in_product_targeting.day" => day,
            "in_product_targeting.cohort" => cohort
          })

          total_deleted
        rescue ActiveRecord::ActiveRecordError => e
          GitHub.logger.error("Failed to delete IpmMatches", {
            "in_product_targeting.error" => e.message,
            "in_product_targeting.day" => day,
            "in_product_targeting.cohort" => cohort
          })
          raise e
        end
      end
    end

    # Deletes all IpmMatches with day on or before the specified day across all entity types (users, organizations, enterprises).
    #
    # @param day [String] The day in ISO 8601 format (YYYY-MM-DD).
    # @return [Integer] The total number of deleted matches across all tables.
    sig { params(day: String).returns(Integer) }
    def delete_matches_on_or_before_day(day:)
      return 0 if GitHub.multi_tenant_enterprise? || GitHub.enterprise?

      GitHub.logger.info("Deleting matches on or before day", {
        "in_product_targeting.day" => day
      })

      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          # Parse the input day to ensure valid date format
          target_date = Date.parse(day)

          # Convert target date to string format appropriate for comparison
          target_date_str = target_date.to_s

          # Batch delete records to avoid performance issues with large deletes
          deleted_count = 0

          # Delete from user matches table
          ::IpmMatch.where("day <= ?", target_date_str).in_batches do |batch|
            # Get the IDs first to avoid the "can't specify target table in FROM clause" error
            ids = batch.pluck(:id)
            # Delete records with those IDs
            deleted_count += ::IpmMatch.where(id: ids).delete_all
          end

          # Delete from organization matches table
          ::IpmOrganizationMatch.where("day <= ?", target_date_str).in_batches do |batch|
            ids = batch.pluck(:id)
            deleted_count += ::IpmOrganizationMatch.where(id: ids).delete_all
          end

          # Delete from enterprise matches table
          ::IpmEnterpriseMatch.where("day <= ?", target_date_str).in_batches do |batch|
            ids = batch.pluck(:id)
            deleted_count += ::IpmEnterpriseMatch.where(id: ids).delete_all
          end

          # Delete from repository matches table
          ::IpmRepositoryMatch.where("day <= ?", target_date_str).in_batches do |batch|
            ids = batch.pluck(:id)
            deleted_count += ::IpmRepositoryMatch.where(id: ids).delete_all
          end

          GitHub.logger.info("Successfully deleted IpmMatches on or before date", {
            "in_product_targeting.deleted_count" => deleted_count,
            "in_product_targeting.day" => day,
            "in_product_targeting.target_date" => target_date.to_s
          })

          deleted_count
        rescue ArgumentError => e
          GitHub.logger.error("Invalid date format for day parameter", {
            "in_product_targeting.error" => e.message,
            "in_product_targeting.day" => day
          })
          raise e
        rescue ActiveRecord::ActiveRecordError => e
          GitHub.logger.error("Failed to delete IpmMatches on or before date", {
            "in_product_targeting.error" => e.message,
            "in_product_targeting.day" => day
          })
          raise e
        end
      end
    end

    # Deletes all IpmMatches for a specific user.
    # Does not delete matches on enterprise or multi-tenant enterprise environments.
    #
    # @param user_id [Integer] The ID of the user whose matches should be deleted.
    # @return [Integer] The number of deleted matches.
    sig { params(user_id: Integer).returns(Integer) }
    def delete_matches_for_user(user_id:)
      return 0 if GitHub.enterprise? || GitHub.multi_tenant_enterprise?

      ActiveRecord::Base.connected_to(role: :writing) do
        ::IpmMatch.where(user_id: user_id).delete_all
      end
    end

    # Returns the count of IpmMatches for a specific user.
    #
    # @param user_id [Integer] The ID of the user.
    # @return [Integer] The number of matches for the user.
    sig { params(user_id: Integer).returns(Integer) }
    def matches_count_for_user(user_id:)
      return 0 if GitHub.multi_tenant_enterprise? || GitHub.enterprise?

      ::IpmMatch.where(user_id: user_id).count
    end
  end
end
