# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillGhesIssueAttachments < Base
      class Issue < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :issues
      end

      class UserAsset < ApplicationRecord::Domain::AssetObjects
        self.table_name = :user_assets
      end

      class Attachment < ApplicationRecord::Domain::AssetObjects
        self.table_name = :attachments
      end

      sig { returns(Date) }
      def self.missing_data_lower_bound
        # We can use a release date of 3.13.0, 2024-06-03, as the lower bound for missing data
        # This is the date when private assets were introduced in GitHub Enterprise Server
        Date.new(2024, 6, 3)
      end

      iterate_over :database_table, params: {
           model_class: Issue,
           columns: [:id, :user_id, :compressed_body, :repository_id],
           # Only process issues that were created after 3.13.0 was released
           conditions: "created_at > '#{missing_data_lower_bound}'",
      }

      sig { override.void }
      def after_initialize
        # Use the same GUID regex pattern as ClusterScanner
        @guid_regex = T.let(/(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}/, T.nilable(Regexp))
        # Match urls like http://172.28.128.4/storage/user/123/files/guid
        @cluster_asset_re = T.let(%r{#{GitHub.storage_cluster_url}\/user\/(\d+)\/files\/(#{@guid_regex})}, T.nilable(Regexp))
        # Match the storage cluster URL with isolated subdomain
        @cluster_asset_subdomain_re = T.let(%r{#{storage_cluster_url_isolated_subdomain_complement}\/user\/(\d+)\/files\/(#{@guid_regex})}, T.nilable(Regexp))
        # Match urls like http://172.28.128.4/download/user/123/files/guid
        @private_mode_cluster_asset_re = T.let(%r{#{GitHub.storage_private_mode_url}\/user\/(\d+)\/files\/(#{@guid_regex})}, T.nilable(Regexp))

        @cluster_private_asset_re = T.let(%r{\/assets\/(\d+)\/(#{@guid_regex})}, T.nilable(Regexp))
      end

      sig { returns(T.nilable(Regexp)) }
      def storage_cluster_url_isolated_subdomain_complement
        # If the storage cluster URL is nil, we shouldn't try to generate a complement
        if GitHub.storage_cluster_url.nil?
          nil
        elsif GitHub.subdomain_isolation?
          # If we are using isolated subdomains, we need to remove the subdomain from the URL and append 'storage' after the host
          Regexp.new(GitHub.storage_cluster_url.sub(%r{(https?)://[^.]+\.(.+)}, '\1://\2') + "/storage")
        else
          # If we are not using isolated subdomains, we need to remove storage from the path and append the 'media' subdomain to the beginning of the host
          Regexp.new(GitHub.storage_cluster_url.sub(%r{(https?://)([^/]+)/(storage)?/?(.*)}, '\1media.\2\4'))
        end
      end


      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        return if items.empty?

        asset_matches_by_issue_id = {}

        # Process each issue's body and find asset URLs
        items.each do |id, val|
          issue_id = id
          body = val[:compressed_body]
          user_id = val[:user_id]
          repository_id = val[:repository_id]

          if body && user_id && repository_id
            begin
              # Decompress the body content
              result = Zstd.decompress(body)

              # Scan the body for asset URLs
              matches = scan_for_assets(result).uniq

              if matches.any?
                asset_matches_by_issue_id[issue_id] = {
                  matches: matches,
                  user_id: user_id,
                  repository_id: repository_id
                }
                log "Found #{matches.length} asset matches in issue #{issue_id}"
              end
            rescue StandardError => e
              log "Error processing issue #{issue_id}: #{e.message}"
            end
          end
        end
        return if asset_matches_by_issue_id.empty?

        # Create Attachment records for each match
        if dry_run?
          log "Would create #{asset_matches_by_issue_id.values.sum { |v| v[:matches].length }} attachments across #{asset_matches_by_issue_id.keys.length} issues"
        else
          create_attachments(asset_matches_by_issue_id)
        end
      end

      sig { params(text: String, regex: T.nilable(Regexp)).returns(T::Array[T::Array[String]]) }
      def scan_regex_in_body(text, regex)
        return [] unless regex
        # String#scan returns an array of matches
        # - For regexes with capture groups, each match is an array of the captured groups
        # - For regexes without capture groups, each match is a string
        text.scan(regex).map { |match| match.is_a?(String) ? [match] : match }
      end

      sig { params(body: String).returns(T::Array[T::Hash[Symbol, String]]) }
      def scan_for_assets(body)
        matches = []

        # Look for cluster storage URLs
        # Format: storage_url/user/123/files/guid
        # Captures: [0]=user_id, [1]=guid
        scan_regex_in_body(body, @cluster_asset_re).each do |match|
          user_id, guid = match[0], match[1]
          matches << { user_id: user_id, guid: guid }
        end

        # Look for cluster storage URLs with the subdomain complement
        # Format: subdomain_complement_storage_url/user/123/files/guid
        # Captures: [0]=user_id, [1]=guid
        scan_regex_in_body(body, @cluster_asset_subdomain_re).each do |match|
          user_id, guid = match[0], match[1]
          matches << { user_id: user_id, guid: guid }
        end

        # Look for private asset URLs
        # Format: private_url/user/123/files/guid
        # Captures: [0]=user_id, [1]=guid
        scan_regex_in_body(body, @private_mode_cluster_asset_re).each do |match|
          user_id, guid = match[0], match[1]
          matches << { user_id: user_id, guid: guid }
        end

        # Look for legacy canonical URLs
        # Format: /assets/123/guid
        # Captures: [0]=user_id, [1]=guid
        scan_regex_in_body(body, @cluster_private_asset_re).each do |match|
          user_id, guid = match[0], match[1]
          matches << { user_id: user_id, guid: guid }
        end

        matches
      end

      sig { params(asset_matches_by_issue: T::Hash[Integer, T::Hash[Symbol, T.untyped]]).void }
      def create_attachments(asset_matches_by_issue)
        asset_matches_by_issue.each do |issue_id, data|
          matches = data[:matches]
          user_id = data[:user_id]
          repository_id = data[:repository_id]
          # Try to find all the corresponding UserAsset records
          assets = find_assets(matches)

          if assets.empty?
            log "No assets found for issue #{issue_id} matches"
            next
          end
          # Create attachment records
          write_to(model_class: Attachment) do
            attach_assets_to_issue(issue_id, assets, user_id, repository_id)
            log "Created #{assets.length} attachments for issue #{issue_id}"
          end
        end
      end

      sig { params(matches: T::Array[T::Hash[Symbol, String]]).returns(T::Array[UserAsset]) }
      def find_assets(matches)
        assets = []
        guids = matches.map { |match| match[:guid] }.uniq
        begin
          # Fetch all UserAssets with the given GUIDs in one query
          assets = UserAsset.where(guid: guids).to_a
        rescue ActiveRecord::StatementInvalid => e
          log "Invalid SQL statement: #{e.message}"
          return []
        end
        assets.compact
      end

      sig { params(issue_id: Integer, assets: T::Array[UserAsset], user_id: Integer, repository_id: Integer).void }
      def attach_assets_to_issue(issue_id, assets, user_id, repository_id)
        return if assets.empty?

        now = Time.current
        asset_ids = assets.map(&:id)

        # Prepare values for bulk insert
        values = asset_ids.map do |asset_id|
          [
            user_id,                    # attacher_id
            asset_id,                   # asset_id
            "UserAsset",                # asset_type
            issue_id,                   # attachable_id
            "Issue",                    # attachable_type
            now,                        # created_at
            now,                        # updated_at
            repository_id,              # entity_id
            "Repository"                # entity_type
          ]
        end

        # Use bulk insertion for performance
        values.each_slice(100) do |batch|
          sql_bindings = {
            values: Arel::Nodes::ValuesList.new(batch),
            updated_at: now,
          }

          sql = Arel.sql <<-SQL, **sql_bindings
            INSERT INTO `attachments`
              (`attacher_id`, `asset_id`, `asset_type`, `attachable_id`, `attachable_type`,
               `created_at`, `updated_at`, `entity_id`, `entity_type`)
            :values
            ON DUPLICATE KEY UPDATE `updated_at` = :updated_at
          SQL

          ActiveRecord::Base.connected_to(role: :writing) do
            Attachment.connection.insert(sql)
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillGhesIssueAttachments.new(args).run
end
