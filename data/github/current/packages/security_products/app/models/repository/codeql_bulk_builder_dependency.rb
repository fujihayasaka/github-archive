# typed: true
# frozen_string_literal: true

module Repository::CodeqlBulkBuilderDependency
  extend T::Helpers
  requires_ancestor { Repository }

  # Get the list of languages currently onboarded for bulk building for the this repository.
  def languages_onboarded_for_codeql_bulk_building
    CodeqlBulkBuilderConfig
      .where(repository_id: id)
      .pluck(:language)
  end

  # Onboards the given language to CodeQL bulk building.
  # This is idempotent and will not affect any other languages that this repository is onboarded for.
  # Returns true if the language was newly-onboarded, or false if it was already onboarded.
  def onboard_language_for_codeql_bulk_building(language)
    CodeqlBulkBuilderConfig.retry_on_find_or_create_error do
      if CodeqlBulkBuilderConfig.where(repository_id: id).where(language: language).count == 0
        CodeqlBulkBuilderConfig.create!(
          repository_id: id,
          language: language,
          last_attempted: CodeqlBulkBuilderConfig::NEVER_HAPPENED,
        )
        return true
      else
        return false
      end
    end
  end

  # Offboards the given language from CodeQL bulk building.
  # This is idempotent and will not affect any other languages that this repository is onboarded for.
  # Returns true if the language was previously onboarded, or false if not.
  def offboard_language_from_codeql_bulk_building(language)
    CodeqlBulkBuilderConfig
      .where(repository_id: id)
      .where(language: language)
      .delete_all > 0
  end
end
