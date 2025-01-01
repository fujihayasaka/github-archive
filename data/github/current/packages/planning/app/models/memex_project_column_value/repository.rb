# typed: strict
# frozen_string_literal: true

class MemexProjectColumnValue::Repository < T::Struct
  include MemexProjectColumnValue::SerializableValue

  const :id, Integer
  const :is_forked, T::Boolean
  const :is_public, T::Boolean
  const :is_archived, T::Boolean
  const :has_issues, T::Boolean
  const :name, String
  const :owner, String
  const :name_with_display_owner, String
  const :url, String

  sig { override.returns(MemexProjectColumn::IDataSource::JSONValue) }
  def to_hash
    {
      id: id,
      isForked: is_forked,
      isPublic: is_public,
      isArchived: is_archived,
      hasIssues: has_issues,
      name: name,
      owner: owner,
      nameWithOwner: name_with_display_owner,
      url: url,
    }
  end

  sig { override.returns(String) }
  def to_s
    name_with_display_owner
  end

  sig { override.returns(String) }
  def to_csv
    name_with_display_owner
  end
end
