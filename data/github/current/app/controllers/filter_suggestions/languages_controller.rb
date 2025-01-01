# typed: true
# frozen_string_literal: true

class FilterSuggestions::LanguagesController < ApplicationController
  include FilterSuggestions::FilterSuggestionsDependency

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    optional: false, only: [:index]

  before_action :login_required

  def index
    languages = languages_from_query.map do |language|
      {
        name: language.name,
        color: language.color || LanguageHelper::FALLBACK_COLOR,
      }
    end

    respond_payload({ languages: languages })
  end

  private

  def languages_from_query
    query = params[:filter_value]&.downcase || ""
    languages = Linguist::Language.all
    if query.present?
      languages.select! do |language|
        language.name.downcase.start_with?(query) || language.aliases.any? { |a| a.downcase.start_with?(query) }
      end
    end
    languages
  end

  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
