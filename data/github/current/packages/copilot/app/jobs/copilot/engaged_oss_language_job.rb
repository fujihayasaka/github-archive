# typed: strict
# frozen_string_literal: true

module Copilot
  class EngagedOssLanguageJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC
    gate_with_feature_flag :copilot_engaged_oss_job

    # Language is a string from the LANGUAGES array in EngagedOssJob.
    sig { params(language: T.nilable(String)).void }
    def perform(language: nil)
      # The language is nil when we want to send for all languages.
      if language.nil?
        Copilot::LanguageRepositoryLoader.call(all_languages: true)
      else
        # if the language isn't nil, we need to make sure it's a real language
        language_name = LanguageName.find_by(name: language)

        unless language_name.present?
          GitHub.logger.info(
            "Language not found",
            "gh.copilot.flag_enabled" => flag_enabled,
            "gh.programming_language" => language,
          )
          return
        end

        Copilot::LanguageRepositoryLoader.call(language_name: language_name)
      end
      GitHub.logger.info("Finished Copilot::EngagedOssLanguageJob", "gh.programming_language" => language)
    end
  end
end
