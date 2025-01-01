# typed: strict
# frozen_string_literal: true

module Releases
  ICreateReleaseAttributes = T.type_alias do
    {
      repository_id:  Integer,
      author_id:  Integer,
      tag_name:  T.nilable(String),
      name:  T.nilable(String),
      body:  T.nilable(String),
      draft:  T.nilable(T::Boolean),
      prerelease:  T.nilable(T::Boolean),
      target_commitish:  T.nilable(String),
      generate_release_notes:  T.nilable(T::Boolean),
      make_latest:  T.nilable(T::Boolean),
    }
  end
end
