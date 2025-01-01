# typed: true
# frozen_string_literal: true

class IntegrationSingleFile < ApplicationRecord::Collab
  extend GitHub::Encoding
  force_utf8_encoding :path

  # rubocop:todo Rails/InverseOf
  belongs_to :version,
    class_name:  "IntegrationVersion",
    foreign_key: :integration_version_id,
    required:    true
  # rubocop:enable Rails/InverseOf
  validates :path, presence: true, uniqueness: { scope: :version, case_sensitive: true }, length: { maximum: 255 }

  validate :path_sanity

  def path_sanity
    return unless path
    unless sanitized_path == path
      errors.add :path, "contains invalid characters"
    end
  end

  # Hoisted from ActiveStorage::Filename#sanitize
  # https://api.rubyonrails.org/classes/ActiveStorage/Filename.html#method-i-sanitized
  def sanitized_path
    path.strip.tr("\u{202E}\u{202B}\u{200F}%$|:;\t\r\n\\", "-")
  end
end
