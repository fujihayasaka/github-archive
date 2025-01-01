# typed: true
# frozen_string_literal: true

module Api::Serializer::CodeqlDatabaseDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::UserDependency }

  # Creates a Hash to be serialized to JSON.
  #
  # database - CodeqlDatabase
  # options - Hash
  #
  # Returns a Hash if the codeql database upload exists, otherwise nil.
  def codeql_database_upload_hash(database, options = {})
    return nil unless database

    repository = database.repository
    download_path = "/repositories/#{repository.id}/code-scanning/codeql/databases/#{database.language}"

    {
      id: database.id,
      name: database.name,
      language: database.language,
      uploader: simple_user_hash(database.uploader, content_options(options)),
      content_type: database.content_type,
      size: database.size,
      created_at: time(database.created_at),
      updated_at: time(database.updated_at),
      url: url(download_path, options),
      commit_oid: database.commit_oid,
    }
  end

  def codeql_database_array_upload_hash(data, options = {})
    return nil unless data

    databases = data.fetch(:databases, [])
    databases.map { |d| codeql_database_upload_hash(d, options) }
  end
end
