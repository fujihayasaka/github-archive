# typed: true
# frozen_string_literal: true

module GitHubModels
  class CalculateModelPopularityJob < GitHubModelsJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 1.day, condition: -> { GitHub.models_enabled? }

    BATCH_SIZE = 100

    # https://data.githubapp.com/sql/share/86daf9ce
    QUERY = <<~SQL
      SELECT context['registry'] AS registry,
          context['model'] AS model_name,
          COUNT(DISTINCT actor_id) AS total_unique_users
      FROM delta.hydro.analytics_v0_browser_event
      WHERE event = 'github_models.playground.chat_request.sent'
      AND day >= format_datetime(date_add('day', -1, current_date), 'yyyy-MM-dd')
      GROUP BY context['registry'], context['model']
    SQL

    sig { void }
    def perform
      return unless GitHub.models_enabled?

      trino_results = GitHub.trino.run_with_names(QUERY)
      model_slugs = model_slugs_from(trino_results)
      results_by_registry_and_name = group_results_by_registry_and_name(trino_results)
      @used_model_slugs = Set.new

      model_slugs.each_slice(BATCH_SIZE) do |model_slugs_in_batch|
        process_batch(model_slugs_in_batch, results_by_registry_and_name)
      end

      reset_popularity_of_unused_models
    end

    private

    sig do
      params(
        model_slugs_in_batch: T::Array[String],
        results_by_registry_and_name: T::Hash[String, T::Hash[String, T::Hash[String, T.untyped]]]
      ).void
    end
    def process_batch(model_slugs_in_batch, results_by_registry_and_name)
      models = GitHubModels.domain.models.find_many(slugs: model_slugs_in_batch)
      models_by_registry_and_name = group_models_by_registry_and_name(models)

      models_by_registry_and_name.each do |registry, models_by_name|
        results_by_name = results_by_registry_and_name[registry] || {}
        next if results_by_name.empty?

        models_by_name.each do |model_name, model|
          result = results_by_name[model_name]
          update_model(model, result) if result
        end
      end
    end

    sig { params(model: GitHubModels::IModel, presto_result: T::Hash[String, T.untyped]).void }
    def update_model(model, presto_result)
      popularity = presto_result["total_unique_users"]
      @used_model_slugs << model.slug
      success = with_write { GitHubModels.domain.models.update_popularity(model, popularity) }

      unless success
        GitHub.dogstats.increment("github_models.calculate_model_popularity_failure",
          tags: ["model:#{model.name}"],
        )
      end
    end

    sig { void }
    def reset_popularity_of_unused_models
      @used_model_slugs.each_slice(BATCH_SIZE) do |used_slugs_in_batch|
        with_write do
          models = GitHubModels.domain.models.find_many(slugs_to_exclude: used_slugs_in_batch)
          GitHubModels.domain.models.reset_popularity(models)
        end
      end
    end

    sig { params(trino_results: T::Array[T.untyped]).returns(T::Array[String]) }
    def model_slugs_from(trino_results)
      slugs = trino_results.map do |result|
        registry = result["registry"]
        model_name = result["model_name"]
        next if registry.blank? || model_name.blank?

        GitHubModels.domain.models.slug_for(registry: registry, name: model_name)
      end
      slugs.compact
    end

    sig do
      params(
        models: T::Array[GitHubModels::IModel]
      ).returns(T::Hash[String, T::Hash[String, GitHubModels::IModel]])
    end
    def group_models_by_registry_and_name(models)
      models.each_with_object({}) do |model, hash|
        registry = model.registry&.downcase

        if registry.present?
          hash[registry] ||= {}
          name = model.name&.downcase

          if name.present?
            hash[registry][name] = model
          end
        end
      end
    end

    sig do
      params(
        trino_results: T::Array[T::Hash[String, T.untyped]]
      ).returns(T::Hash[String, T::Hash[String, T::Hash[String, T.untyped]]])
    end
    def group_results_by_registry_and_name(trino_results)
      trino_results.each_with_object({}) do |result, hash|
        registry = result["registry"]&.downcase
        model_name = result["model_name"]&.downcase

        if registry.present?
          hash[registry] ||= {}

          if model_name.present?
            hash[registry][model_name] = result
          end
        end
      end
    end
  end
end
