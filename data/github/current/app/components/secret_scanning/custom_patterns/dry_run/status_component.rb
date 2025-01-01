# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module DryRun
      class StatusComponent < ApplicationComponent
        attr_reader :pattern_id, :pattern_owner_id, :pattern_scope, :dry_run_info

        include SecretScanningCustomPatternsHelper

        def initialize(pattern_id:, pattern_owner_id:, pattern_scope:, dry_run_info:, user:)
          @pattern_id = pattern_id
          @pattern_owner_id = pattern_owner_id
          @pattern_scope = pattern_scope
          @dry_run_info = dry_run_info
          @user = user
        end

        def status
          SecretScanningCustomPatternsHelper::dry_run_status(dry_run_info)
        end

        def time_elapsed
          return nil if dry_run_info.nil? || dry_run_info[:finished_at].nil? || dry_run_info[:started_at].nil?
          dry_run_info[:finished_at].seconds - dry_run_info[:started_at].seconds
        end

        def show_repo_count?
          true unless pattern_scope == :repo_scope
        end

        def repo_count
          return "-" if dry_run_info.nil?
          return "0" if dry_run_info[:scan_status_counts].is_a?(Array)
          dry_run_info[:scan_status_counts].to_s
        end

        def total_result_count
          return 0 if dry_run_info.nil?

          dry_run_info[:total_result_count]
        end

        # Valid results are in repos that are part of the scope of the pattern, and
        # are secret scanning enabled
        memoize def valid_results
          results_in_enabled_repos = results_from_enabled_repos

          # Filter out results that are in repos that are not part of the scope of the pattern
          results_in_enabled_repos.select { |result| is_result_viewable?(result, pattern_scope) }
        end

        memoize def results_from_deleted_repos
          results_in_enabled_repos = results_from_enabled_repos

          results_in_enabled_repos.select { |result| result_repo(result).nil? }
        end

        def is_result_viewable?(result, pattern_scope)
          repo = result_repo(result)
          return false if repo.nil?

          case pattern_scope
          when :repo_scope
            true
          when :org_scope
            repo_owner(repo).id == pattern_owner_id
          when :business_scope
            owner = repo.owner
            return false if owner.nil?

            if owner.is_a?(Organization)
              business = repo_business(repo)
              return false if business.nil?
              business.id == pattern_owner_id &&
                (repo_owner(repo).adminable_by?(@user) || SecurityProduct::SecurityManagers.new(owner).users.include?(@user))
            elsif owner.is_a?(User)
              ghas_for_emus = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(repo.owner)
              ghas_for_emus.feature_available?
            end
          end
        end

        def result_repo(result)
          ActiveRecord::Base.connected_to(role: :reading) do
            Repository.find_by(id: result.repository_id)
          end
        end

        def repo_owner(repo)
          ActiveRecord::Base.connected_to(role: :reading) do
            repo.owner
          end
        end

        def repo_business(repo)
          ActiveRecord::Base.connected_to(role: :reading) do
            repo.owner.business
          end
        end

        def status_text
          return "In progress" if status == :INPROGRESS
          return "Error" if status == :FAILED
          return "No dry runs queued" if status == :NOT_DRY_RUN
          status.to_s.humanize
        end

        def show_red_status_text?
          status == :CANCELLED
        end

        def total_duration_text
          case time_elapsed
          when nil
            "-"
          when 0..1
            "< 1s"
          when 1..60
            "#{time_elapsed}s"
          when 60..3600
            "#{(time_elapsed / 60).round}m"
          else
            "> 1h"
          end
        end

        def total_matches_text
          if total_result_count.zero? || valid_results.empty?
            return "-" if status == :INPROGRESS || status == :UNKNOWN || status == :NOT_DRY_RUN
            return "0"
          end
          return "> #{GitHub.secret_scanning_max_dry_run_results}" if total_result_count > GitHub.secret_scanning_max_dry_run_results
          total_result_count.to_s
        end

        def show_blankslate?
          valid_results.empty? || valid_results.nil?
        end

        def blankslate_heading
          return "Something went wrong" if valid_results.nil?
          return "Dry run queued" if status == :QUEUED
          return "Dry run in progress" if status == :INPROGRESS
          return "No dry runs queued" if status == :UNKNOWN || status == :NOT_DRY_RUN
          "No matches found"
        end

        def blankslate_description
          return "Unable to fetch dry run results, please try again" if valid_results.nil?

          case status
          when :COMPLETED
            return "Expecting something? Try changing your secret format"
          when :CANCELLED
            return "Dry run cancelled"
          when :FAILED
            return "Dry run failed to complete. Please try again"
          when :INPROGRESS, :UNKNOWN
            return "Nothing to display yet. Click refresh above to check again"
          when :NOT_DRY_RUN
            return "Nothing to display yet. Queue a dry run to see results"
          end

          "No results found." if valid_results.empty?
        end

        def previous_cursor
          return nil if dry_run_info.nil? || dry_run_info[:previous_cursor].empty? || valid_results.empty?
          Base64.urlsafe_encode64(dry_run_info[:previous_cursor])
        end

        def next_cursor
          return nil if dry_run_info.nil? || dry_run_info[:next_cursor].empty? || valid_results.empty?
          Base64.urlsafe_encode64(dry_run_info[:next_cursor])
        end

        def cursor_path
          case pattern_scope
          when :repo_scope
            get_custom_pattern_dry_run_results_by_cursor_path(id: pattern_id, previous_cursor: previous_cursor, next_cursor: next_cursor)
          when :org_scope
            settings_org_security_analysis_get_custom_pattern_dry_run_results_by_cursor_path(id: pattern_id, previous_cursor: previous_cursor, next_cursor: next_cursor)
          when :business_scope
            settings_business_get_custom_pattern_dry_run_results_by_cursor_enterprise_path(id: pattern_id, previous_cursor: previous_cursor, next_cursor: next_cursor)
          else
            ""
          end
        end

        def show_path
          case pattern_scope
          when :repo_scope
            show_custom_pattern_path(id: pattern_id)
          when :org_scope
            settings_org_security_analysis_show_custom_pattern_path(id: pattern_id)
          when :business_scope
            settings_business_show_custom_pattern_enterprise_path(id: pattern_id)
          else
            ""
          end
        end

        def has_pagination?
          return false if previous_cursor.nil? && next_cursor.nil?
          return false if valid_results.empty?

          true
        end

        def cursor_disabled?(cursor)
          return true if cursor.nil? || cursor.empty?

          false
        end

        private

        memoize def results_from_enabled_repos
          return [] if dry_run_info.nil?

          # Get a list of repos associated with the results
          result_repo_ids = dry_run_info[:results].collect(&:repository_id).uniq

          # Filter out results that are in repos where token scanning is not enabled.
          # TODO move this out of component?
          token_scanning_enabled_repo_ids = SecretScanning::Services::CustomPatternsService.new(@user).validate_secret_scanning_repositories(result_repo_ids)
          return nil if token_scanning_enabled_repo_ids.nil?

          results_in_enabled_repos = dry_run_info[:results].select { |result| token_scanning_enabled_repo_ids.include?(result.repository_id) }
        end
      end
    end
  end
end
