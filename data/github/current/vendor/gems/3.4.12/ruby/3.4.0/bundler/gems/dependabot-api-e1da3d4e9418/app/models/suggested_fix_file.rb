# frozen_string_literal: true

class SuggestedFixFile < ApplicationRecord
  belongs_to :suggested_fix

  validates :suggested_fix_id, presence: true
  validates :file_path, presence: true, length: { maximum: 4096 }
  validates :file_path_hash, presence: true, length: { is: 32 }
  validates :file_checksum, presence: true, length: { is: 20 }
  validates :diff_content, presence: true
end
