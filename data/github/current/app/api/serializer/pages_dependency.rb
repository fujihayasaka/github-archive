# typed: false
# frozen_string_literal: true

module Api::Serializer::PagesDependency
  def pages_deployment_hash(status, options = {})
    return nil unless status
    {
      id: status[:deployment_id],
      page_url: status[:page_url],
      status_url: url("/repos/#{status[:repository].name_with_owner_for_api(use: options[:serialize_login])}/pages/deployment/status/#{status[:deployment_id]}", options),
      preview_url: status[:preview_url]
    }
  end

  def pages_deployment_status_hash(status, options = {})
    return nil unless status
    {
      status: status[:status]
    }
  end
end
