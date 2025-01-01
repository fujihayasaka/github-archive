# typed: false
# frozen_string_literal: true

module User::LanguagesDependency
  STARRED_REPO_LANGUAGE_BREAKDOWN_LIMIT = 10_000

  # Get the user's primary language from database cache,
  # or update it on the fly if not found.
  #
  # Returns primary language name as a String.
  def primary_language
    return @primary_language unless @primary_language.blank?

    language_id = self.primary_language_name_id
    @primary_language = language_id.present? ? LanguageName.find_by_id(language_id) : calculate_primary_language!
  end

  # Public: Returns the most common language from the set of public,
  # active repositories that the user owns.
  #
  # Returns a LanguageName record, nil otherwise.
  def calculate_primary_language!
    return unless id
    primary_lang_name_id = Repository.connection.select_value(Arel.sql(<<-SQL, user_id: id))
      SELECT primary_language_name_id, count(*) as total FROM repositories
      WHERE repositories.owner_id = :user_id
        AND repositories.public = 1
        AND repositories.active = 1
        AND primary_language_name_id IS NOT NULL
      GROUP BY primary_language_name_id
      ORDER BY total DESC
      LIMIT 1
    SQL
    @primary_language = LanguageName.find(primary_lang_name_id) if primary_lang_name_id

    if @primary_language
      ActiveRecord::Base.connected_to(role: :writing) do
        self.update_column(:primary_language_name_id, @primary_language.id)
      end
    end

    @primary_language
  end

  def starred_repositories_by_language(language_limit: nil, apply_star_limit: true)
    return {} if apply_star_limit && too_many_stars_for_language_breakdown?

    repo_id_language_breakdown(visible_starred_repositories.pluck(:id), language_limit)
  end

  def starred_public_repositories_by_language(language_limit: nil)
    return {} if too_many_stars_for_language_breakdown?

    repo_language_breakdown(starred_repositories.public_scope, language_limit)
  end

  def repo_language_breakdown(repos, limit)
    repo_id_language_breakdown(repos.pluck(:id), limit)
  end

  def repo_id_language_breakdown(repo_ids, limit)
    ActiveRecord::Base.connected_to(role: :reading) do
      # Returns an Hash of { repo.primary_language_name_id => total, ... }
      repo_primary_language_name_ids_and_totals = Repository.batched_scope(:id, values: repo_ids) do |scope|
        scope.where("primary_language_name_id is NOT NULL")
      end.pluck(:primary_language_name_id).tally.to_a.sort_by(&:last).reverse.to_h
      repo_primary_language_name_ids_and_totals = repo_primary_language_name_ids_and_totals.take(limit).to_h if limit.present?

      language_name_ids = repo_primary_language_name_ids_and_totals.map(&:first)
      language_names_by_id = LanguageName.ids_and_names(language_name_ids)

      language_names_by_id.map do |id, name|
        total = repo_primary_language_name_ids_and_totals[id]
        [name, total]
      end.to_h
    end
  end

  private

  def too_many_stars_for_language_breakdown?
    return false unless GitHub.flipper[:starred_repo_language_breakdown_limit].enabled?(self)

    user_metadata && user_metadata.stars_count > STARRED_REPO_LANGUAGE_BREAKDOWN_LIMIT
  end
end
