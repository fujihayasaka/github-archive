# typed: true
# frozen_string_literal: true

# This model is intentionally empty. The secret-scanning team is in the process
# of moving their database cluster into their own managed cluster. Long term,
# models such as this (and TokenScanResult) would likely be removed or gutted
# like this model.
#
# Currently however, they are still critical in test setup that requires seeding
# the database in order to record VCR cassettes.
class TokenScanResultLocation < ApplicationRecord::TokenScanningService
  self.table_name = "token_scan_result_locations_v2"

  belongs_to :token_scan_result, touch: true
  alias_method :result, T.unsafe(:token_scan_result)

  # Find or create a location for the given parent result and found token.
  #
  # Returns the location that was either created or already existed.
  def self.create_from_found_token!(result, found_token)
    attributes = {
      token_scan_result_id: result.id,
      repository_id: result.repository_id,
      path: found_token.path,
      commit_oid: found_token.commit,
      start_line: found_token.start_line || 0,
      end_line: found_token.end_line || 0,
      start_column: found_token.start_column || 0,
      end_column: found_token.end_column || 0,
      content_type: found_token&.content_type,
      content_number: found_token&.content_number,
      content_id: found_token&.content_id,
    }
    create_attributes = attributes.merge({
      blob_oid: found_token.blob,
    })
    location = retry_on_find_or_create_error do
      find_by(attributes) || create!(attributes.merge(create_attributes))
    end

    if result.first_location_id.nil? || result.first_location_id == 0
      result.update!(first_location_id: location.id)
    end

    result.update!(has_valid_locations: true)

    location
  end

  # Find or create a location for the given parent result and found token.
  #
  # Returns the location that was either created or already existed.
  def self.create_ignored_alert_from_found_token!(result, found_token)
    attributes = {
      token_scan_result_id: result.id,
      repository_id: result.repository_id,
      path: found_token.path,
      commit_oid: found_token.commit,
      start_line: found_token.start_line || 0,
      end_line: found_token.end_line || 0,
      start_column: found_token.start_column || 0,
      end_column: found_token.end_column || 0,
      content_type: found_token&.content_type,
      content_number: found_token&.content_number,
      content_id: found_token&.content_id,
      ignore_token: true,
    }
    create_attributes = attributes.merge({
      blob_oid: found_token.blob,
    })
    location = retry_on_find_or_create_error do
      find_by(attributes) || create!(attributes.merge(create_attributes))
    end

    location
  end
end
