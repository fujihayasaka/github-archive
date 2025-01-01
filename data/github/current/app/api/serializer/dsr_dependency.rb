# typed: true
# frozen_string_literal: true

module Api::Serializer::DsrDependency
  def dsr_export_request_hash(user_data, options = {})
    user_data
  end

  def dsr_status_request_hash(status_message, options = {})
    status_message
  end
end
