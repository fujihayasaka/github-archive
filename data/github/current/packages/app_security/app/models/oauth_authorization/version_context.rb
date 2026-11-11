# typed: strict
# frozen_string_literal: true

class OauthAuthorization
  class VersionContext < T::Struct
    const :default_content_references, T::Hash[String, String]
    const :default_events, T::Array[String]
    const :default_permissions, T::Hash[String, Symbol]
    const :number, Integer
    const :single_file_paths, T::Array[String]
    const :user_permissions, T::Hash[String, Symbol]
  end
end
