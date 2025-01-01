# typed: true
# frozen_string_literal: true

class SearchCustomScope < ApplicationRecord::Collab
  MAX_CUSTOM_SCOPES = 10
  MAX_NAME_LENGTH = 50
  MAX_QUERY_LENGTH = 500

  belongs_to :user

  attr_accessor :name_validation_only

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }, uniqueness: { scope: :user_id }
  validates :query, presence: true, length: { maximum: MAX_QUERY_LENGTH }, unless: :name_validation_only

  validate :limit_number_of_custom_scopes, on: :create, unless: :name_validation_only
  validate :name_cannot_start_with_at_symbol, :name_cannot_contain_slashes_or_double_quotes

  private

  def limit_number_of_custom_scopes
    if user && T.must(user).search_custom_scopes.size >= MAX_CUSTOM_SCOPES
      errors.add(:base, "You can only have #{MAX_CUSTOM_SCOPES} custom scopes")
    end
  end

  def name_cannot_start_with_at_symbol
    if name.start_with?("@")
      errors.add(:name, "can't start with '@'")
    end
  end

  def name_cannot_contain_slashes_or_double_quotes
    if name.include?("/") || name.include?("\"")
      errors.add(:name, "can't contain slashes (/) or double quotes (\")")
    end
  end

end
