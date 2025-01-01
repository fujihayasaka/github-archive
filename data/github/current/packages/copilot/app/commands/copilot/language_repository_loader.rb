# typed: strict
# frozen_string_literal: true

module Copilot
  class LanguageRepositoryLoader < Command

    sig { params(language_name: T.nilable(LanguageName), all_languages: T::Boolean).void }
    def initialize(language_name: nil, all_languages: false)
      @language_name         = T.let(language_name, T.nilable(LanguageName))
      @all_languages         = T.let(all_languages, T::Boolean)
      @loaded_repositories   = T.let([], T::Array[Repository])
      @existing_repositories = T.let(Set.new, T::Set[[Integer, Integer]])
      @new_repositories      = T.let(Set.new, T::Set[[Integer, Integer]])
    end

    # This method does three things:
    #
    # 1. It loads the list of engaged repositories from the database
    # 2. It loads the list of Copilot::EngagedOssRepository records for the language and deletes them from the db
    # 3. It inserts the new records into the db
    # 4. It kicks off jobs for each repository to update the users
    sig { override.void }
    def perform
      with_read do
        load_repositories
        return unless @loaded_repositories.any?

        reset_table
        insert_new_records
        record_churn
        schedule_jobs
      end
    end

    # Loads up the top 1000 repositories for the language that fit the criteria:
    #
    # Created over a month ago
    # Pushed to over a year ago
    # With 25 or more forks
    # With 500 or more stargazers
    sig { void }
    def load_repositories
      GitHub.logger.info(
        "Loading repositories",
        "gh.copilot.language_repo_loader.language_name" => @language_name,
        "gh.copilot.language_repo_loader.all_languages" => @all_languages,
        "gh.copilot.language_repo_loader.language" => @language_name&.name,
      )

      @loaded_repositories, time = value_with_timing do
        from_scope = "repositories IGNORE INDEX (index_on_public_and_primary_language_name_id_and_parent_id)"
        repos = Repository.from(from_scope).
          includes(:repository_licenses).
          references(:repository_licenses).
          merge(RepositoryLicense.where(license_id: licenses))

        repos = repos.where(primary_language_name_id: @language_name.id) if @language_name.present? && !@all_languages

        repos = repos.where(public: true, active: true, parent_id: nil).
          where("repositories.created_at < ?", 1.month.ago).
          where("repositories.pushed_at > ? OR repositories.created_at > ?", 1.year.ago, 1.year.ago).
          where("public_fork_count >= 25").
          where("watcher_count >= 500").
          order("watcher_count DESC").
          order("public_fork_count DESC").
          limit(1000)

        repos.to_a
      end

      GitHub.logger.info(
        "Loaded repositories",
        "gh.copilot.language_repo_loader.language_name" => @language_name,
        "gh.copilot.language_repo_loader.all_languages" => @all_languages,
        "gh.copilot.language_repo_loader.language" => @language_name&.name,
        "gh.copilot.language_repo_loader.loaded_repositories.count" => @loaded_repositories.length,
        "gh.copilot.language_repo_loader.time" => time,
      )
    end

    sig { void }
    def reset_table
      # we need a language to delete for all languages
      return if @all_languages

      @existing_repositories = Copilot::EngagedOssRepository.where(language_name: @language_name).pluck(:repository_id, :rank).to_set

      GitHub.logger.info(
        "Deleting existing records",
        "gh.copilot.language_repo_loader.language_name" => @language_name,
        "gh.copilot.language_repo_loader.all_languages" => @all_languages,
        "gh.copilot.language_repo_loader.language" => @language_name&.name,
        "gh.copilot.language_repo_loader.loaded_repositories.count" => @loaded_repositories.length,
        "gh.copilot.language_repo_loader.existing_repositories.count" => @existing_repositories.length,
      )

      count = with_write do
        Copilot::EngagedOssRepository.where(language_name: @language_name).delete_all
      end

      GitHub.logger.info(
        "Deleted existing records",
        "gh.copilot.language_repo_loader.deleted.count" => count,
        "gh.copilot.language_repo_loader.language_name" => @language_name,
        "gh.copilot.language_repo_loader.all_languages" => @all_languages,
        "gh.copilot.language_repo_loader.language" => @language_name&.name,
        "gh.copilot.language_repo_loader.loaded_repositories.count" => @loaded_repositories.length,
        "gh.copilot.language_repo_loader.existing_repositories.count" => @existing_repositories.length,
      )
    end

    sig { void }
    def insert_new_records
      engaged_repositories_inserts = Array.new

      @loaded_repositories.each_with_index do |repository, index|
        repository_id = repository.id.to_i
        license_id = repository.repository_licenses.first&.license_id
        @new_repositories << [repository_id, index + 1]

        engaged_repositories_inserts << {
          repository_id: repository.id,
          language_name_id: repository.primary_language_name_id.to_i,
          fork_count: repository.public_fork_count.to_i,
          last_pushed_at: repository.pushed_at || repository.created_at,
          license_id: license_id,
          rank: @all_languages ? 0 : index + 1,
          stargazer_count: repository.send(:stargazer_count).to_i, # have to do this because RenameColumn
        }
      end

      GitHub.logger.info(
        "Inserting new records",
        "gh.copilot.language_repo_loader.inserted.count" => engaged_repositories_inserts.count,
        "gh.copilot.language_repo_loader.language_name" => @language_name,
        "gh.copilot.language_repo_loader.all_languages" => @all_languages,
        "gh.copilot.language_repo_loader.language" => @language_name&.name,
        "gh.copilot.language_repo_loader.loaded_repositories.count" => @loaded_repositories.length,
        "gh.copilot.language_repo_loader.existing_repositories.count" => @existing_repositories.length,
      )

      with_write do
        Copilot::EngagedOssRepository.insert_all(engaged_repositories_inserts)
      end
    end

    sig { void }
    def record_churn
      language = @all_languages ? "all" : @language_name&.name
      changes = @existing_repositories - @new_repositories

      GitHub.dogstats.histogram("copilot.engaged_oss_repository.churn", changes.count, tags: ["language:#{language}"])

      GitHub.logger.info(
        "Churn",
        "gh.copilot.language_repo_loader.changes.count" => changes.count,
        "gh.copilot.language_repo_loader.changes" => changes.to_a,
        "gh.copilot.language_repo_loader.language_name" => @language_name,
        "gh.copilot.language_repo_loader.all_languages" => @all_languages,
        "gh.copilot.language_repo_loader.language" => @language_name&.name,
        "gh.copilot.language_repo_loader.loaded_repositories.count" => @loaded_repositories.length,
        "gh.copilot.language_repo_loader.existing_repositories.count" => @existing_repositories.length,
      )
    end

    sig { void }
    def schedule_jobs
      @new_repositories.each do |repository_id, _rank|
        Copilot::EngagedOssRepositoryUserJob.perform_later(repository_id)
      end
    end

    sig { returns(T::Array[Integer]) }
    def licenses
      License::IDS_TO_LICENSES.drop(2).map do |license|
        license[0].to_i
      end
    end
  end
end
