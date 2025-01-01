# typed: true
# frozen_string_literal: true

module Api::Serializer
  class FileContentTextMatch
    include TextMatch

    def self.supported_field_names
      %w(file filename path).freeze
    end

    def object_type
      "FileContent"
    end

    def object_url_suffix
      "/repositories/#{repository_id}/contents/#{file_path}?ref=#{commit_sha}"
    end

    def property
      case field_name
      when "file" then "content"
      when "filename" then "path"
      when "path" then "path"
      end
    end

    private

    def file_info
      search_result.fetch("_source", {})
    end

    def repository_id
      file_info["repo_id"]
    end

    def file_path
      [file_info["path"], file_name].join("/")
    end

    def file_name
      file_info["filename"]
    end

    def commit_sha
      file_info["commit_sha"]
    end
  end
end
