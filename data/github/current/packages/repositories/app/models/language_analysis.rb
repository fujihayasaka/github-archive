# typed: true
# frozen_string_literal: true

class LanguageAnalysis
  # Initialize a new language analysis for one or more repositories.
  #
  # repositories - one or more Repository instances.
  def initialize(repositories)
    @repositories = repositories
  end

  # Public: Get a list of programming languages and the percentage each one
  # represents in the repository.
  #
  # Returns an Array of [["language name", percentage], ...], ordered by
  # descending percentage and ascending by name. Percentages are rounded to the
  # nearest tenth of a percent.
  def language_percentages
    sizes = language_sizes
    total_size = sizes.sum(&:last)

    percentages = sizes.map do |name, size|
      percent = if total_size > 0
        ((size / total_size.to_f) * 100).round(1)
      else
        0
      end
      [name, percent]
    end

    round_percentages(percentages)
  end

  # Because we're only presenting one decimal place to the user, the total
  # percent sometimes fails to add up to 100%.  To avoid confusion, we try
  # to ensure the sum of all languages is 100% by adding the remainder to the
  # most popular programming language.
  # 100 = 99.9 + 0.1
  def round_percentages(percentages)
    sum = percentages.sum(&:last)
    if sum > 0 && sum != 100
      difference = 100 - sum
      name, size = percentages[0]
      percentages[0] = [name, (size + difference).round(1)]
    end

    percentages
  end

  # Public: Get a list of languages and the sizes of each one in a repository
  # or group of repositories. In descending order of size.
  def language_sizes
    sizes_by_name_id = T.cast(Language.
      where(repository: @repositories).
      group(:language_name_id).
      order("sum_size DESC, language_name_id DESC").
      sum(:size), T::Hash[Integer, Integer])
    names_by_id = LanguageName.
      where(id: sizes_by_name_id.keys).
      pluck(:id, :name).to_h

    languages = sizes_by_name_id.transform_keys do |name_id|
      names_by_id[name_id]
    end.to_a

    sort_by_percent_and_name(languages)
  end

  # This function takes an array of languages along with
  # their percenteges and sorts them by descending percentage
  # and ascending by name
  def sort_by_percent_and_name(pairs)
    pairs.sort { |a, b| [b[1], a[0]] <=> [a[1], b[0]] }
  end

  # Public: Summarize the language percentages by combining some as "Other".
  # If more languages than the limit, combine the extras as Other.
  # If fewer than the limit, combine any under the percentage threshold.
  # Returns hash of language name to percentage
  def language_summary(limit: 7, threshold: 1)
    percents = language_percentages
    non_zero = percents.count { |_, percent| percent > 0 }

    langs, other =
      if non_zero == limit
        [percents, []]
      elsif non_zero > limit
        [percents.take(limit - 1), percents.drop(limit - 1)]
      else
        percents.partition { |_, percent| percent > threshold }
      end

    other.sum(&:last).round(1).tap do |other_total|
      langs << ["Other", other_total] if other_total > 0
    end

    langs.to_h
  end
end
