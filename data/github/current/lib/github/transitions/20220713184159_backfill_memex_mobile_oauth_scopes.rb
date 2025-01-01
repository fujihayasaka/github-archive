# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
require "divvy"

module GitHub
  module Transitions
    # The surface area of this class should only provide the following public methods:
    #   #after_initialize
    #   #dispatch
    #   #process
    #   #perform
    class BackfillMemexMobileOauthScopes < Transition
      include Divvy::Parallelizable

      BATCH_SIZE        = 100
      UPDATE_BATCH_SIZE = 1
      SCOPES_TO_ADD     = %w[project].freeze
      APPLICATION_KEYS  = [
        Apps::Internal::Mobile::GITHUB_MOBILE_IOS_CLIENT_ID,
        Apps::Internal::Mobile::GITHUB_MOBILE_ANDROID_CLIENT_ID
      ].to_a.freeze

      private_constant :BATCH_SIZE, :UPDATE_BATCH_SIZE, :SCOPES_TO_ADD, :APPLICATION_KEYS

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          OauthAccess.github_sql.value("SELECT COALESCE(MIN(id), 0) FROM oauth_accesses")
        end

        max_id = @other_args[:end_id] || readonly do
          OauthAccess.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM oauth_accesses")
        end

        batch_size      = @other_args[:batch_size] || BATCH_SIZE
        application_ids = fetch_mobile_application_ids
        log("[#after_initialize] min_id: #{min_id}, max_id: #{max_id}, batch_size: #{batch_size}, application_ids: #{application_ids}")

        # We will not be able to find any mobile tokens if we first cannot find any mobile applications.
        @do_not_perform = application_ids.empty?

        if do_not_perform
          log("This transition has been marked as do-not-perform by after_initialize since no mobile apps were found.")

          return
        end

        @iterator = OauthAccess.github_sql_batched_between(
          start: min_id,
          finish: max_id,
          batch_size: batch_size
        )

        @iterator.add(<<-SQL, application_ids: application_ids)
          -- id must go first for batched between to work properly
          SELECT
            oauth_accesses.id,
            oauth_accesses.raw_data,
            oauth_authorizations.id,
            oauth_authorizations.scopes
          FROM oauth_accesses
          INNER JOIN oauth_authorizations ON oauth_authorizations.id = oauth_accesses.authorization_id
          WHERE
            oauth_accesses.id BETWEEN :start AND :last AND
            oauth_accesses.application_id IN :application_ids
        SQL

        @handler = Coders::Handler.new(Coders::OauthAccessCoder)
      end

      def dispatch
        if do_not_perform
          log("[#dispatch] This transition has been marked as do-not-perform.")

          return
        end

        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          log("Batch with IDs: #{rows.map { |item| item[0] }}") if verbose?

          yield rows
        end
      end

      def perform
        if do_not_perform
          log("[#perform] This transition has been marked as do-not-perform.")

          return
        end

        dispatch { |rows| process(rows) }
      end

      def process(rows)
        rows.each_slice(UPDATE_BATCH_SIZE) do |slice|
          OauthAccess.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log("Attemping to add scopes to: #{slice.map { |item| item[0] }}") if verbose?

            oauth_accesses = []
            oauth_auths    = []

            # loop through each oauth_access record and its corresponding oauth_authorization record.
            # There is a concern here that since it is a 1:many relationship that we may update
            # the same oauth_authorizations record multiple times.
            slice.each do |access_id, access_raw_data, auth_id, auth_raw_data|
              access_coder = handler.load(access_raw_data)

              if (SCOPES_TO_ADD - access_coder.scopes).any?
                access_coder.scopes = Api::AccessControl.normalize_scopes(
                  access_coder.scopes + SCOPES_TO_ADD,
                  visibility: :all
                )

                raw_data = handler.dump(access_coder)

                oauth_accesses << [access_id, raw_data]
              else
                log("Skipping OauthAccess #{access_id} because it already has all the scopes") if verbose?
              end

              auth_scopes = JSON.parse(auth_raw_data)

              if (SCOPES_TO_ADD - auth_scopes).any?
                auth_scopes = Api::AccessControl.normalize_scopes(
                  auth_scopes + SCOPES_TO_ADD,
                  visibility: :all
                )

                raw_data = auth_scopes.to_json

                oauth_auths << [auth_id, raw_data]
              else
                log("Skipping OauthAuthorization #{auth_id} because it already has all the scopes") if verbose?
              end
            end

            run_oauth_accesses_batch_update(oauth_accesses) if oauth_accesses.any? && !dry_run?
            run_oauth_auths_batch_update(oauth_auths) if oauth_auths.any? && !dry_run?
          end
        end
      end

      private

      attr_reader :handler, :iterator, :do_not_perform

      def fetch_mobile_application_ids
        readonly do
          OauthApplication.github_sql.values(<<-SQL, application_keys: APPLICATION_KEYS)
            SELECT id
            FROM oauth_applications
            WHERE `key` IN :application_keys
          SQL
        end
      end

      def run_oauth_accesses_batch_update(rows)
        ActiveRecord::Base.connected_to(role: :writing) do
          sql = OauthAccess.github_sql.new("UPDATE oauth_accesses SET raw_data = CASE")

          rows.each do |(id, raw_data)|
            sql.add(<<~SQL, id: id, raw_data: GitHub::SQL.BINARY(raw_data))
              WHEN id = :id THEN :raw_data
            SQL
          end

          sql.add("END WHERE id IN :ids", ids: rows.map { |item| item[0] })
          sql.run
          sql.affected_rows
        end
      end

      def run_oauth_auths_batch_update(rows)
        ActiveRecord::Base.connected_to(role: :writing) do
          sql = OauthAccess.github_sql.new("UPDATE oauth_authorizations SET scopes = CASE")

          rows.each do |(id, scopes)|
            sql.add(<<~SQL, id: id, scopes: scopes)
              WHEN id = :id THEN :scopes
            SQL
          end

          sql.add("END WHERE id IN :ids", ids: rows.map { |item| item[0] })
          sql.run
          sql.affected_rows
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::BackfillMemexMobileOauthScopes.new(**options)
  divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  divvy.run
end
