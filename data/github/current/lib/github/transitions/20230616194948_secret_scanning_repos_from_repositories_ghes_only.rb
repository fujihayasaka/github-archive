# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    # rubocop:disable GitHub/NoGitHubSql
    class SecretScanningReposFromRepositoriesGhesOnly < Transition

      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1

      attr_reader :iterator
      attr_reader :total_updated

      SS_REPO_COLUMNS = [
        :id,
        :owner_scope_id,
        :full_refresh_source_updated_at,
        :business_id,
        :visibility,
        :default_ref,
        :parent_repository_id,
        :scannable,
        :ghas_secret_scanning_enabled,
        :results_visible,
        :created_at,
        :updated_at].freeze
      SS_REPO_COLUMN_LITERALS = SS_REPO_COLUMNS.map { |c| GitHub::SQL::LITERAL(c) }

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        min_id = @other_args[:start_id] || 0
        max_id = @other_args[:end_id] || readonly { ApplicationRecord::Domain::Repositories.github_sql.value("SELECT COALESCE(MAX(id), 0) FROM repositories") }
        batch_size = read_batch_size

        log "inserting repositories => start_id:#{min_id}, end_id:#{max_id}, batch_size:#{batch_size}"
        @total_updated = 0
        @iterator = ApplicationRecord::Domain::Repositories.github_sql_batched(start: min_id, limit: batch_size)

        @iterator.add <<-SQL, max: max_id
          SELECT id
          FROM repositories
          WHERE id > :last
          AND id <= :max
          ORDER BY id ASC
          LIMIT :limit
        SQL
      end

      # Returns nothing.
      def perform
        unless GitHub.enterprise?
          return nil
        end
        GitHub::SQL::Readonly.new(iterator.batches).each { |rows| process(rows) }
        if verbose?
          verb = dry_run? ? "Would have updated" : "Updated"
          log("#{verb} #{@total_updated} repositories")
        end
      end

      private

      def process(rows)
        scopes_dict = { "ORG" => {}, "USER" => {} }
        repos_with_owner_scopes = []
        rows.each do |repo_id|
          ss_repo_data = get_ss_repo_fields(repo_id)
          next if ss_repo_data.nil?
          owner_id = ss_repo_data.repo.owner_id
          owner_scope_type = get_owner_scope_type(ss_repo_data.repo)
          next unless owner_scope_type
          owner_scope = scopes_dict[owner_scope_type][owner_id]

          unless dry_run?
            owner_scope ||= ensure_owner_scope(owner_id, owner_scope_type)
            next unless owner_scope
            scopes_dict[owner_scope_type][owner_id] = owner_scope
            ss_repo_data.owner_scope_id = owner_scope.id
          end

          repos_with_owner_scopes << ss_repo_data
        end

        if dry_run? && verbose?
          @total_updated += repos_with_owner_scopes.length
        else
          repos_with_owner_scopes.each_slice(write_batch_size) do |batch|
            @total_updated += batch_insert_repos(batch)
          end
        end
        if verbose?
          log("processed repos #{rows.first} through #{rows.last}")
        end
      end

      def get_owner_scope_type(repo)
        if repo.owner.is_a?(Organization)
          "ORG"
        elsif repo.owner.is_a?(User)
          "USER"
        else
          nil
        end
      end

      def get_ss_repo_fields(repo_id)
        repo = Repository.find_by(id: repo_id)
        return nil unless repo

        ss_repo = SecretScanning::SecretScanningRepo.find_by(id: repo_id)
        if ss_repo
          return nil
        end

        # insert into secret_scanning_repos
        token_scanning = SecretScanning::Features::Repo::TokenScanning.new(repo)
        public_scanning = SecretScanning::Features::Repo::PublicScanning.new(repo)
        scannable = token_scanning.enabled? || public_scanning.enabled?
        ghas_secret_scanning_enabled = repo.advanced_security_enabled? && token_scanning.enabled?
        results_visible = token_scanning.enabled?
        business_id = nil
        unless repo.organization_id.nil?
          sql = Arel.sql <<-SQL, org_id: repo.organization_id
            SELECT business_id
            FROM business_organization_memberships
            WHERE organization_id=:org_id
          SQL
          business_id = ApplicationRecord::Domain::Users.connection.select_value(sql)
        end

        SSRepo.new({
          repo: repo,
          scannable: scannable,
          ghas_secret_scanning_enabled: ghas_secret_scanning_enabled,
          results_visible: results_visible,
          business_id: business_id,
        })
      end

      def ensure_owner_scope(owner_id, scope)
        # ensure owner scope exists
        owner_scope = T.let(nil, T.nilable(SecretScanning::OwnerScope))
        ActiveRecord::Base.connected_to(role: :writing) do
          owner_scope = SecretScanning::OwnerScope.find_by(owner_id: owner_id, owner_scope: scope)
          unless owner_scope
            SecretScanning::OwnerScope.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              SecretScanning::OwnerScope.retry_on_find_or_create_error do
                SecretScanning::OwnerScope.create(owner_id: owner_id, owner_scope: scope)
              end
            end
          end
        end
      end

      def batch_insert_repos(repos_with_owner_scopes)
        update_time = Time.now
        ActiveRecord::Base.connected_to(role: :writing) do
          SecretScanning::SecretScanningRepo.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            repo_entries = GitHub::SQL::ROWS(repos_with_owner_scopes.map do |repo_with_owner_scope|
              [
                repo_with_owner_scope.repo.id,
                repo_with_owner_scope.owner_scope_id,
                update_time,
                repo_with_owner_scope.business_id || GitHub::SQL::NULL,
                repo_with_owner_scope.repo.visibility.upcase,
                GitHub::SQL::NULL,
                repo_with_owner_scope.repo.parent_id || GitHub::SQL::NULL,
                repo_with_owner_scope.scannable,
                repo_with_owner_scope.ghas_secret_scanning_enabled,
                repo_with_owner_scope.results_visible,
                update_time,
                update_time,
              ]
            end)
            ApplicationRecord::TokenScanningService.github_sql.run <<-SQL, columns: SS_REPO_COLUMN_LITERALS, values: repo_entries
              INSERT INTO secret_scanning_repos :columns
              VALUES :values
            SQL
          end
        end
        repos_with_owner_scopes.length
      rescue ActiveRecord::RecordNotUnique
        0
      end
    end
    # rubocop:enable GitHub/NoGitHubSql

    class SSRepo
      def initialize(hash)
        @repo = hash[:repo]
        @owner_scope_id = hash[:owner_scope_id]
        @scannable = hash[:scannable]
        @ghas_secret_scanning_enabled = hash[:ghas_secret_scanning_enabled]
        @results_visible = hash[:results_visible]
        @business_id = hash[:business_id]
      end

      attr_accessor :repo, :owner_scope_id, :scannable, :ghas_secret_scanning_enabled, :results_visible, :business_id
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{__FILE__} [options]"

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

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |size|
      options[:read_batch_size] = size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |size|
      options[:write_batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]

  if GitHub.enterprise?
    # If choosing to run this transition as a single process, uncomment the below commands:
    transition = GitHub::Transitions::SecretScanningReposFromRepositoriesGhesOnly.new(**options)
    transition.run
    # If choosing to use Divvy and run this transition as a multithreaded process
    # uncomment the below commands to pass the transition to Divvy, as well as an
    # option for worker count:
    # transition = GitHub::Transitions::SecretScanningReposFromRepositoriesGhesOnly.new(**options)
    # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
    # divvy.run
  end
end
