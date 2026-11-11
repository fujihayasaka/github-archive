# typed: true
# frozen_string_literal: true

module Api::Serializer::PorterDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  def porter_import_hash(import, options = {})
    repository_api_path = "/repos/#{options.repo.name_with_owner_for_api(use: options[:serialize_login])}"

    result = {}

    # Ensure that the "vcs" field is present. If it's set, it'll be
    # updated in the next step.
    result["vcs"] = import["vcs"]

    # Add (most of) the rest of the data that porter returned.
    result.update(import)
    result.delete "url"

    # Translate some data

    if authors_count = result.delete("authors_found")
      result["authors_count"] = authors_count
    end

    if result.has_key?("percent")
      result["import_percent"] = result.delete("percent")
    end

    # Include large file info when status indicates that ImportRepositoryJob has finished
    if result.has_key?("has_large_files")
      unless %w[complete pushing waiting_to_push].include? result["status"]
        result.delete "has_large_files"
        result.delete "large_files_count"
        result.delete "large_files_size"
      end
    end

    case result["status"]
    when "auth"
      result.update \
        "status" => "detection_needs_auth",
        "message" => "Authorization for #{result["vcs_url"]} is required. Please refer to the documentation for instruction on how to provide your credentials."
    when "none"
      result.update \
        "status" => "detection_found_nothing",
        "message" => "No projects were found at the given url."
    when "choose"
      result.update \
        "status" => "detection_found_multiple",
        "message" => "Multiple projects were found at the given url. Please refer to the documentation for instruction on how to provide your project choice."
    when "setup"
      result.update \
        "status" => "importing",
        "import_percent" => nil,
        "commit_count" => nil
    when "auth_failed"
      result.update \
        "message" => "Authorization for #{result["vcs_url"]} failed. Please refer to the documentation for instruction on how to provide your credentials."
    when "error"
      if porter_error_message = result.delete("error_message").presence
        result["message"] = porter_error_message
      end
    end

    # Add hypermedia URLs.
    result.update \
      url: url("#{repository_api_path}/import", options),
      html_url: "#{options.repo.permalink}/import",
      authors_url: url("#{repository_api_path}/import/authors", options),
      repository_url: url(repository_api_path, options)

    result
  end

  def porter_author_hash(author, options = {})
    author_id = author.fetch("id")
    import_api_path = "/repos/#{options.repo.name_with_owner_for_api(use: options[:serialize_login])}/import"
    {
      id: author_id,
      remote_id: author["remote_id"],
      remote_name: author["remote_name"],
      email: author["email"] || author["remote_id"],
      name: author["name"] || author["remote_name"],
      url: url("#{import_api_path}/authors/#{author_id}", options),
      import_url: url(import_api_path, options),
    }
  end

  def porter_large_files_hash(large_file, options = {})
    large_file
  end
end
