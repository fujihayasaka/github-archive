# typed: true
# frozen_string_literal: true

module Repositories
  # Renders an ELM-specific source-repository banner that overrides the generic
  # archived-repo notice for repositories participating in an Enterprise Live Migration.
  #
  # The message is driven by the repository's elm_migration_state:
  #
  #   started / resources_sent    - migration in progress, repo still editable
  #   locked / live_updates_sent  - cutover in progress, repo is now read-only
  #   complete                    - migration finished; links to destination repo
  class ElmMigrationSourceNoticeComponent < ApplicationComponent
    sig { params(repository: Repository).void }
    def initialize(repository:)
      @repository = repository
    end

    sig { returns(String) }
    def call
      elm_config = ElmMigrationStateConfig.new(@repository)
      case elm_config.elm_migration_state
      when *Configurable::RepositoryElmMigrationState::EDITABLE_STATES
        editable_notice
      when *Configurable::RepositoryElmMigrationState::CUTOVER_STATES
        cutover_notice(elm_config.elm_migration_destination_url)
      when Configurable::RepositoryElmMigrationState::COMPLETE_STATE
        complete_notice(elm_config.elm_migration_destination_url)
      else
        safe_join([])
      end
    end

    private

    sig { returns(T.untyped) }
    def editable_notice
      html_escape(
        "Live migration in progress. You can keep working in this repository while data synchronizes to the destination."
      )
    end

    sig { params(destination_url: T.nilable(String)).returns(T.untyped) }
    def cutover_notice(destination_url)
      prefix = html_escape(
        "This repository has been archived as part of an active migration and is now read-only. " \
        "No changes can be made here. After final synchronization is complete, make all updates in "
      )

      if destination_url.present?
        safe_join([prefix, link_to(destination_url, destination_url), html_escape(".")])
      else
        safe_join([prefix, html_escape("the destination repository.")])
      end
    end

    sig { params(destination_url: T.nilable(String)).returns(T.untyped) }
    def complete_notice(destination_url)
      if destination_url.present?
        safe_join([
          "This repository has been migrated to ",
          link_to(destination_url, destination_url),
          "."
        ])
      else
        html_escape("This repository has been migrated to another location.")
      end
    end
  end
end
