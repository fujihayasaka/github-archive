# typed: true
# frozen_string_literal: true

module OctoDb::LikeQuery
  extend T::Helpers

  requires_ancestor { T.class_of(ActiveRecord::Base) }

  # Query for values with the specified prefix.
  #
  # column - The column to query.
  # prefix - The value prefix to query for.
  #
  # Returns an ActiveRecord::Relation
  def with_prefix(column, prefix)
    where("#{column} LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(prefix)}%")
  end

  # Query for values without the specified prefix.
  #
  # column - The column to query.
  # prefix - The value prefix to query for.
  #
  # Returns an ActiveRecord::Relation
  def without_prefix(column, prefix)
    where("#{column} NOT LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(prefix)}%")
  end

  # Query for values with the specified suffix.
  #
  # column - The column to query.
  # suffix - The value suffix to query for.
  #
  # Returns an ActiveRecord::Relation
  def with_suffix(column, suffix)
    where("#{column} LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(suffix)}")
  end

  # Query for values with the specified substring.
  #
  # column    - The column to query.
  # substring - The value substring to query for.
  #
  # Returns an ActiveRecord::Relation
  def with_substring(column, substring)
    where("#{column} LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(substring)}%")
  end

  # Query for values with the specified substrings.
  # If more than one substring is provided,
  # they are joined with an OR.
  #
  # column     - The column to query.
  # substrings - The array of substrings to query for.
  #
  # Returns an ActiveRecord::Relation
  def with_substrings(column, substrings)
    if !substrings.is_a?(Array) || substrings.empty?
      raise ArgumentError, "substrings must be an array with at least one element"
    end

    conditions = T.let(nil, T.nilable(ActiveRecord::Relation))
    substrings.each do |substring|
      condition = unscoped.where("#{column} LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(substring)}%")
      conditions = conditions ? conditions.or(condition) : condition
    end

    # Without this there is a chance that we will end up with an `OR` query that
    # falls outside the expected scope:
    # ```
    #   WHERE id = 123
    #   AND (name like 'foobar')
    #   OR (name LIKE 'barbaz')`
    # ```
    # this guarantees that our new relation will be AND'd to the conditions of the existing query.
    # ```
    #   WHERE id = 123
    #   AND (name like 'foobar' OR name LIKE 'barbaz')`
    # ```
    merge(conditions)
  end

  # Query for values without the specified substrings.
  # If more than one substring is provided,
  # they are joined with an AND.
  #
  # column     - The column to query.
  # substrings - The array of substrings to query for.
  #
  # Returns an ActiveRecord::Relation
  def without_substrings(column, substrings)
    if !substrings.is_a?(Array) || substrings.empty?
      raise ArgumentError, "substrings must be an array with at least one element"
    end

    substrings.reduce(self) do |rel, substring|
      rel.where("#{column} NOT LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(substring)}%")
    end
  end
end
