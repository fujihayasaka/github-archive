# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module DryRun
      class RepoSelectorDialogComponent < ApplicationComponent
        attr_reader :custom_pattern_owner, :mode, :selected_repo_ids, :scheme, :disabled

        def initialize(
          custom_pattern_owner:,
          mode:,
          selected_repo_ids:,
          scheme:,
          disabled:
        )
          @custom_pattern_owner = custom_pattern_owner
          @mode = mode
          @selected_repo_ids = selected_repo_ids
          @scheme = scheme
          @disabled = disabled
        end

        def dry_run_button_disabled?
          return false if all_repos_radio_button_checked?
          selected_repos_radio_button_checked? && (selected_repo_ids.nil? || selected_repo_ids.empty?)
        end

        def dry_runs_allowed_on_all_repos?
          @custom_pattern_owner.is_a?(Organization)
        end

        def all_repos_radio_button_checked?
          return false unless @custom_pattern_owner.is_a?(Organization)
          return false if @mode == :create
          @selected_repo_ids.empty?
        end

        def selected_repos_radio_button_checked?
          return true if @mode == :create
          !@selected_repo_ids.empty?
        end
      end
    end
  end
end
