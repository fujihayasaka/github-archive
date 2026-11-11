# typed: true
# frozen_string_literal: true

class UploadDirectoryValidator < ActiveModel::Validator
  # Prevents control characters and path traversal.
  def validate(record)
    directory = record.directory
    return unless directory.present?
    if directory.match(/[^[[:graph:]] ]/) ||
        directory == ".git" ||
        directory.include?("..") ||
        directory.include?("./") ||
        directory.include?("/./") ||
        directory.ends_with?("/.")
      record.errors.add(:directory, "Invalid directory name characters")
    end
  end

  # Removes leading and trailing / path separators. Browser upload paths begin
  # with / because it considers the directory being uploaded to be the root.
  def sanitize_directory_name(name)
    sanitized = (name || "")
      .strip
      .split("/")
      .reject { |s| s == "" }
      .join("/")
    sanitized.present? ? sanitized : nil
  end
end
