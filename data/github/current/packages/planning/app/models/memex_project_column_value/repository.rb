# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::Repository < T::Struct
  const :id, Integer
  const :is_forked, T::Boolean
  const :is_public, T::Boolean
  const :is_archived, T::Boolean
  const :has_issues, T::Boolean
  const :name, String
  const :name_with_display_owner, String
  const :url, String

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def to_hash
    {
      id: id,
      isForked: is_forked,
      isPublic: is_public,
      isArchived: is_archived,
      hasIssues: has_issues,
      name: name,
      nameWithOwner: name_with_display_owner,
      url: url,
    }
  end

  sig { returns(String) }
  def to_csv
    name_with_display_owner
  end
end
