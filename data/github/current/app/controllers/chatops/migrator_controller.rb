# typed: true
# frozen_string_literal: true
require "chatops-controller"
require "github_chatops_extensions"
require "terminal-table"

module Chatops
  class MigratorController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room
    include ::GitHubChatopsExtensions::Checks::Includable::Fido
    include ::GitHubChatopsExtensions::Checks::Includable::Entitlements

    UUID_REGEX = /[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}/
    UUID_LENGTH = 36

    ALLOWED_ROOMS = ["#octoshift-ops"].freeze
    ALLOWED_TEAMS = ["apps/chatops/octoshift-chatops-admin"].freeze
    CONTROLLED_ACTIONS = [:fetch_archive_url].freeze

    MIGRATABLE_RESOURCE_LIMIT = 25

    REMOVE_STRINGS = %w[` tel:].freeze

    # Opt-out of all conditional access and secondary authn checks, since these chatops are run by Hubbers
    # from Slack and the routes for triggering them are only accessible through our internal network
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    before_action -> { T.bind(self, Chatops::MigratorController); require_in_room(ALLOWED_ROOMS) }, only: CONTROLLED_ACTIONS
    before_action :require_fido_2fa, only: CONTROLLED_ACTIONS
    before_action -> { T.bind(self, Chatops::MigratorController); require_ldap_entitlement(ALLOWED_TEAMS) }, only: CONTROLLED_ACTIONS

    chatops_namespace :migrator
    chatops_help "Commands for getting information about legacy import and export API migrations in GitHub"
    chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/). Try re-running the command or ask for help in [#octoshift](https://github.slack.com/archives/CV0E7204X)."

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    private def verify_authenticity_token?
      false # robots do this
    end

    chatop :migration_info,
           /migration_info (?<migration_id>\S+)/,
           "migration_info <migration_id> - get information about an ECI. This works with database ID, GraphQL ID, or migration GUID" do
      migration_id = cleanup_migration_id(jsonrpc_params.require(:migration_id))

      migration_id_valid, error = validate_migration_id(migration_id)
      unless migration_id_valid
        chatop_send(error)
        return
      end

      migration = fetch_migration(migration_id)

      if migration.nil?
        chatop_send("LegacyMigration with ID #{migration_id} could not be found. Please provide a migration_id for a valid LegacyMigration.")
        return
      end

      chat_lines = ["MIGRATION_DATABASE_ID: #{migration.id}"]

      sentry_link = "https://github.sentry.io/issues/?project=1885898&query=is%3Aunresolved+gh.migration_tools.migration.id%3A#{migration.id}&referrer=issue-list&statsPeriod=30d"
      splunk_link = "https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dprod-resque%20#{migration.guid}&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-30d%40d&latest=now&sid=1693416659.2002769_60128E8B-4FAB-4E8C-84E3-B4BD0B0863C6"
      hyperlinks = %(<#{sentry_link}|Sentry Issues>  <#{splunk_link}|Splunk Logs>)

      rows = []

      guid = migration.guid
      created_time = migration.created_at
      updated_time = migration.updated_at
      owner_login = migration.owner.login
      creator_login = migration.creator.login
      state = migration.current_state.name
      migrated_resources_count = migration.migratable_resources.migrated.count
      migrated_resources_percentage = migrated_resources_count / migration.migratable_resources_count.to_f * 100

      rows << %W[`guid` #{migration.guid}]
      rows << %W[`global_relay_id` #{migration.global_relay_id}]
      rows << %W[`state` #{migration.current_state.name}]
      rows << %W[`migratable_resources_count` #{migration.migratable_resources_count}]
      rows << ["`migrated_resources_count`", "#{migrated_resources_count} (#{ActiveSupport::NumberHelper.number_to_percentage(migrated_resources_percentage, precision: 1, strip_insignificant_zeros: true)})"]
      rows << %W[`owner_login` #{migration.owner.login}]
      rows << %W[`owner_id` #{migration.owner.id}]
      rows << %W[`creator_login` #{migration.creator.login}]
      rows << %W[`creator_id` #{migration.creator.id}]
      rows << %W[`created_at` #{migration.created_at}]
      rows << %W[`updated_at` #{migration.updated_at}]
      rows << %W[`lock_repositories` #{migration.lock_repositories}]
      rows << %W[`exclude_attachments` #{migration.exclude_attachments}]
      rows << %W[`exclude_releases` #{migration.exclude_releases}]
      rows << %W[`exclude_owner_projects` #{migration.exclude_owner_projects}]
      rows << %W[`exclude_git_data` #{migration.exclude_git_data}]
      rows << %W[`exclude_metadata` #{migration.exclude_metadata}]
      rows << %W[`org_metadata_only` #{migration.org_metadata_only}]
      rows << %W[`file_exists?` #{migration.file.present?}]
      rows << %W[`file_size` #{migration.file.present? ? ActiveSupport::NumberHelper.number_to_human_size(migration.file.size) : "N/A"}]

      migration_table = Terminal::Table.new do |t|
        t.headings = %w[Attribute Value]
        t.rows = rows
        t.align_column(1, :right)
      end

      chat_lines << "```#{migration_table}```"

      if migration.migratable_resources.any?
        mr_rows = []

        counts = migration.migratable_resources.group(:state, :model_type).count

        # Flipping the keys to be [model_type, state]
        flipped_counts = counts.each_with_object({}) do |((state, model_type), count), new_hash|
          new_hash[[model_type, state]] = count
        end

        flipped_counts.each do |key, value|
          mr_rows << %W[`#{key.join("/")}` #{value}]
        end

        mr_table = Terminal::Table.new do |t|
          t.headings = %w[Model/State Count]
          t.rows = mr_rows
          t.align_column(1, :right)
        end

        chat_lines << "\n"
        chat_lines << "Migratable resources breakdown"
        chat_lines << "```#{mr_table}```"
      end

      chat_lines << hyperlinks

      chatop_send(chat_lines.join("\n"))
      return
    end

    chatop :failed_models,
           /failed_models (?<migration_id>\S+)/,
           "failed_models <migration_id> - Return info about models that failed to import. This works with database ID, GraphQL ID, or migration GUID" do
      migration_id = cleanup_migration_id(jsonrpc_params.require(:migration_id))

      migration_id_valid, error = validate_migration_id(migration_id)
      unless migration_id_valid
        chatop_send(error)
        return
      end

      migration = fetch_migration(migration_id)

      if migration.nil?
        chatop_send("LegacyMigration with ID #{migration_id} could not be found. Please provide a migration_id for a valid LegacyMigration.")
        return
      end

      if migration.migratable_resources.empty?
        chatop_send("LegacyMigration with ID #{migration_id} does not have any migratable resources to report on.")
        return
      end

      failed_migratable_resources = migration.migratable_resources.failed

      if failed_migratable_resources.empty?
        chatop_send("LegacyMigration with ID #{migration_id} does not have any models that failed to import.")
        return
      end

      chat_lines = ["MIGRATION_DATABASE_ID: #{migration.id}"]
      chat_lines << "Total failed models: #{failed_migratable_resources.count}"

      rows = []

      failed_migratable_resources.first(MIGRATABLE_RESOURCE_LIMIT).each do |mr|
        rows << %W[
          #{mr.model_type}
          #{mr.model_id.present? ? mr.model_id : "N/A"}
          #{mr.source_url}
          #{mr.target_url.present? ? mr.target_url : "N/A"}
          #{mr.state}
          #{mr.warning.present? ? mr.warning : "N/A"}
        ]
      end

      table = Terminal::Table.new do |t|
        t.headings = %w[ModelType ModelId SourceUrl TargetUrl State Warning]
        t.rows = rows
        t.align_column(1, :right)
      end

      chat_lines << "\n"
      chat_lines << "List of models that failed to import:"
      chat_lines << "```#{table}```"

      chatop_send(chat_lines.join("\n"))
      return
    end

    chatop :fetch_archive_url,
           /fetch_archive_url (?<migration_id>\S+)/,
           "fetch_archive_url <migration_id> - Fetch a signed download URL for a migration. The URL will be delivered via DM." do
      migration_id = cleanup_migration_id(jsonrpc_params.require(:migration_id))

      migration_id_valid, error = validate_migration_id(migration_id)
      unless migration_id_valid
        chatop_send(error)
        return
      end

      migration = fetch_migration(migration_id)

      if migration.nil?
        chatop_send("LegacyMigration with ID #{migration_id} could not be found. Please provide a migration_id for a valid LegacyMigration.")
        return
      end

      if migration.file.nil?
        chatop_send("Unable to fetch archive download URL due to LegacyMigration with ID #{migration_id} having an expired archive. Consider using the .migrator extend_archive_life chatops in the future to avoid expiration of archive.")
        return
      end

      chat_lines = ["MIGRATION_DATABASE_ID: #{migration.id}"]
      chat_lines << "Archive download URL for LegacyMigration with ID #{migration_id} will be DM'd to you shortly. Please be sure to obtain customer permission to access archive before inspecting metadata files. The link will expire in 1 hour."

      chatop_user = "@#{params[:user]}"
      timestamp = Time.now.utc

      message = <<~HEREDOC
        Below is the archive download URL for requested migration:

        migration_id: #{migration_id}
        Request Date: #{timestamp}
        Download URL: ```#{migration.file.download_url(actor: migration.creator)}````
      HEREDOC
      GitHub::Chatterbox.client.say!(chatop_user, message)

      chatop_send(chat_lines.join("\n"))
      return
    end

    chatop :extend_archive_life,
           /extend_archive_life (?<migration_id>\S+)/,
           "extend_archive_life <migration_id> - Extend the life of a migration archive by 7 days. The URL will be delivered via DM." do
      migration_id = cleanup_migration_id(jsonrpc_params.require(:migration_id))

      migration_id_valid, error = validate_migration_id(migration_id)
      unless migration_id_valid
        chatop_send(error)
        return
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        migration = fetch_migration(migration_id)

        if migration.nil?
          chatop_send("LegacyMigration with ID #{migration_id} could not be found. Please provide a migration_id for a valid LegacyMigration.")
          return
        end

        if migration.file.nil?
          chatop_send("Unable to extend archive life due to LegacyMigration with ID #{migration_id} having an expired archive.")
          return
        end

        migration.file.update_columns(updated_at: 7.days.from_now)

        chat_lines = ["MIGRATION_DATABASE_ID: #{migration.id}"]
        chat_lines << "The archive life for LegacyMigration with ID #{migration_id} has been extended by 7 days. Archive will expire on #{migration.file.updated_at}"

        chatop_send(chat_lines.join("\n"))
        return
      end
    end

    private

    def cleanup_migration_id(migration_id)
      REMOVE_STRINGS.each { |s| migration_id.gsub!(s, "") }
      migration_id.strip
    end

    sig { params(migration_id: String).returns(T::Array[T.any(TrueClass, FalseClass, String, NilClass)]) }
    def validate_migration_id(migration_id)
      return [true, nil] if migration_id.match?(UUID_REGEX) && migration_id.length == UUID_LENGTH
      return [true, nil] if migration_id =~ /\A\d+\z/ # Check if migration_id can be converted to an integer
      return [true, nil] if migration_id.starts_with?("LM")
      return [false, "Invalid migration_id: #{migration_id}. GraphQL ID for RepositoryMigration is not supported. Use the `.octoshift` chatops instead."] if migration_id.start_with?("RM_")
      return [false, "Invalid migration_id: #{migration_id}. GraphQL ID for OrganizationMigration is not supported. Use the `.octoshift` chatops instead."] if migration_id.start_with?("OM_")

      # Default error message
      [false, "Invalid migration_id: #{migration_id}. Please provide a valid migration_id, which can be the databaseId, GraphQL ID (LM_****), or migration GUID."]
    end

    def fetch_migration(migration_id)
      if migration_id.starts_with?("LM")
        Migration.find(Platform::Helpers::GlobalId.parse(migration_id).parts[:id])
      elsif migration_id.match?(UUID_REGEX)
        Migration.find_by(guid: migration_id)
      else
        Migration.find(migration_id)
      end
    rescue Platform::Errors::NotFound, ActiveRecord::RecordNotFound
      nil
    end
  end
end
