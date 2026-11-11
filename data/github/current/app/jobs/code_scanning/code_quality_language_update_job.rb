# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CodeScanning::CodeQualityLanguageUpdateJob < ApplicationJob
  queue_as :code_quality

  before_perform do |job|
    Failbot.push(job: job.class.name)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on(CodeScanning::AutoCodeqlError, attempts: 5, wait: 10.minutes) do |job, error|
    code_quality_error_handler(job, error)
  end

  def self.code_quality_error_handler(job, error)
    # We have been trying to update the languages for a while and it is not working because some other changes
    # are in progress. We should stop trying to update the languages and emit a metric to track this.
    if error.message == "Config update already in progress"
      GitHub.logger.info(
        "Code Quality language update failed - giving up",
        "code.namespace" => "CodeQualityLanguageUpdateJob",
        "gh.repo.id" =>  job.arguments.dig(0, :repository_id),
      )
      GitHub.dogstats.increment("code_quality.language_update.gave_up")
    else
      Failbot.report(error)
    end
  end

  def self.should_perform?(repository:, languages_to_add:, languages_to_delete:)
    CodeQuality.enabled?(repository) && (languages_to_add.present? || languages_to_delete.present?)
  end

  def self.enqueue_if_necessary(repository:, inserted_languages:, removed_languages:)
    languages_to_add = translate_languages(repository:, languages_to_translate: inserted_languages)
    languages_to_delete = translate_languages(repository:, languages_to_translate: removed_languages)

    if should_perform?(repository:, languages_to_add:, languages_to_delete:)
      # The new job will read data written by this job. Therefore, we defer its execution by a few seconds.
      set(wait: 5.seconds).perform_later(repository_id: repository.id, languages_to_add:, languages_to_delete:)
      return true
    end

    false
  end

  def perform(repository_id:, languages_to_add:, languages_to_delete:)
    repository = Repositories::Public.find_active(repository_id)
    # check if code quality was disabled while waiting to start
    return unless CodeScanning::CodeQualityLanguageUpdateJob.should_perform?(repository:, languages_to_add:, languages_to_delete:)
    repository = T.must_because(repository) { "if repository was nil we would have returned early in the preceding line" }

    Failbot.push(
      repository_id: repository.id,
      languages_added: languages_to_add,
      languages_removed: languages_to_delete
    )

    code_quality_enablement = CodeQualityEnablement.new(repository)

    # We do some filtering of the languages here instead of in enqueue_if_necessary to be sure that once we query the existing languages
    # we get the right state, with the added languages already present and the removed not present
    current_supported_languages = code_quality_enablement.language_support.supported_languages

    # The added languages should be present
    languages_to_add = languages_to_add.filter { |language| current_supported_languages.include?(language) }
    languages_to_add.uniq!

    # The removed languages should not be present. If they are present it means that they are one of the combined languages (TS for example)
    # and their counterpart (JS) is still present. In that case we don't want to remove the combined language
    languages_to_delete = languages_to_delete.reject { |language| current_supported_languages.include?(language) }
    languages_to_delete.uniq!

    return unless languages_to_add.present? || languages_to_delete.present?

    # We check if the repository is actually already onboarded. We didn't check this at the time of enqueueing
    # because we want to avoid introducing latency in the linguist job that enqueues this job
    return unless code_quality_enablement.enabled?

    code_quality_enablement.update_languages(languages_to_add: languages_to_add, languages_to_delete: languages_to_delete)
  end

  def self.translate_languages(repository:, languages_to_translate:)
    # Translate languages into the language's canonical names, removing the ones that are not supported by Code Quality
    language_support = CodeScanning::ManagedAnalysesLanguageSupport.new(repository, :CODE_QUALITY)
    language_support.canonical_names(languages_to_translate) & language_support.code_quality_supported_languages
  end
end
