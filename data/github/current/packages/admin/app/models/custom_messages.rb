# typed: true
# frozen_string_literal: true

class CustomMessages < ApplicationRecord::Domain::Users
  include GitHub::Validations
  extend GitHub::Encoding
  force_utf8_encoding :sign_in_message, :sign_out_message, :suspended_message, :announcement

  validates :auth_provider_name, unicode3: true

  UPDATE_QUERY = <<-SQL.freeze
    INSERT INTO #{table_name} (singleton_guard, sign_in_message, sign_out_message, suspended_message, support_url, auth_provider_name, created_at, updated_at)
    VALUES (:singleton_guard, :sign_in_message, :sign_out_message, :suspended_message, :support_url, :auth_provider_name, NOW(), NOW())
    ON DUPLICATE KEY UPDATE
      sign_in_message     = VALUES(sign_in_message),
      sign_out_message    = VALUES(sign_out_message),
      suspended_message   = VALUES(suspended_message),
      support_url         = VALUES(support_url),
      updated_at          = VALUES(updated_at),
      auth_provider_name  = VALUES(auth_provider_name)
  SQL

  def self.instance
    find_by(singleton_guard: 1) || new
  end

  def create_or_update_attributes(attributes = {})
    attributes[:sign_in_message]      ||= (sign_in_message || "")
    attributes[:sign_out_message]     ||= (sign_out_message || "")
    attributes[:suspended_message]    ||= (suspended_message || "")
    attributes[:support_url]          ||= (support_url || "")
    attributes[:auth_provider_name]   ||= (auth_provider_name || "")

    self.class.connection.update(Arel.sql(UPDATE_QUERY,
      singleton_guard:    1,
      sign_in_message:    attributes[:sign_in_message],
      sign_out_message:   attributes[:sign_out_message],
      suspended_message:  attributes[:suspended_message],
      support_url:        attributes[:support_url],
      auth_provider_name: attributes[:auth_provider_name],
    ))
  end
end
