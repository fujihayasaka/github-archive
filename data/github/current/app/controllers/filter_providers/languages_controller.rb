# typed: true
# frozen_string_literal: true

class FilterProviders::LanguagesController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab

  def index
    respond_payload({ languages: languages_from_query.map { |lang| format_response(lang) } })
  end

  def show
    language = Linguist::Language.find_by_name(query_value)

    if language
      respond_payload(format_response(language))
    else
      head :unprocessable_entity
    end
  end

  private

  def languages_from_query
    query = query_value&.downcase || ""
    if repositories_from_query.empty? || query.present?
      languages = Linguist::Language.all
      if query.present?
        languages = languages.select do |language|
          language.name.downcase.start_with?(query) || language.aliases.any? { |a| a.downcase.start_with?(query) }
        end
      end
      languages
    elsif !repositories_from_query.empty?
      languages = []
      repositories_from_query.each do |repo|
        languages << repo.languages.map { |language| language.language_name&.language }
      end

      languages.flatten.uniq
    end
  end

  def format_response(language)
    {
      name: language.name,
      color: language.color || LanguageHelper::FALLBACK_COLOR,
    }
  end

  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
