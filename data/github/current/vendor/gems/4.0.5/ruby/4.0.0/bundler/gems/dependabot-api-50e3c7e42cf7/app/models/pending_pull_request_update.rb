# frozen_string_literal: true

require "rbnacl"

class PendingPullRequestUpdate < ApplicationRecord
  belongs_to :pull_request

  has_one_attached :encrypted_dependency_files_blob

  def updated_dependency_files
    @updated_dependency_files ||=
      begin
        blob = encrypted_dependency_files_blob.download

        encoding = Dependabot::DependencyFile::ContentEncoding::UTF_8
        files = JSON.parse(encrypted_box.decrypt(Base64.strict_decode64(blob)))
        files = files.map(&:symbolize_keys)
        files.map do |file_data|
          Dependabot::DependencyFile.new(
            name: file_data.fetch(:name),
            content: file_data.fetch(:content),
            directory: file_data.fetch(:directory),
            type: file_data.fetch(:type),
            deleted: file_data.fetch(:deleted, false),
            content_encoding: file_data.fetch(:content_encoding, encoding),
            symlink_target: file_data.fetch(:symlink_target, nil),
            mode: file_data.fetch(:mode, nil),
          )
        end
      end
  end

  private

  def encrypted_box
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    RbNaCl::SimpleBox.from_secret_key(token)
  end
end
