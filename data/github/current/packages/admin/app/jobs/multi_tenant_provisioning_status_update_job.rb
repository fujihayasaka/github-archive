# typed: true
# frozen_string_literal: true

class MultiTenantProvisioningStatusUpdateJob < ApplicationJob
  queue_as :multi_tenant_provisioning_status_update

  retry_on_dirty_exit

  schedule interval: 1.hour, condition: -> { !GitHub.single_or_multi_tenant_enterprise? }

  def perform
    MultiTenantProvisioningRequest.in_progress.find_each do |provisioning_request|
      subdomain = provisioning_request.subdomain
      current_step = provisioning_request.provisioning_step

      new_step = provisioning_step(subdomain, current_step)
      next if new_step == current_step

      with_write { provisioning_request.update! provisioning_step: new_step }
    end
  end

  private

  def provisioning_step(subdomain, current_step)
    client = Proxima::Api::TenantMetadataClient.new

    payload = { slug: subdomain }
    response = client.connection.post("/twirp/v0.TenantService/GetTenantProvisioningStatus", payload.to_json)
    return current_step unless response.success?

    response_body = JSON.parse(response.body)
    if response_body["result"] == "Success"
      step_results = response_body["status"]["step_results"]
      return :failed if step_results.any? { |step_result| step_result["status"] == "FAILED" }
      return :completed if step_results.all? { |step_result| step_result["status"] == "COMPLETE" }
      :in_progress
    else
      # Tenants whose provisioning is completed successfully end up getting removed from the records
      # that the /twirp/v0.TenantService/GetTenantProvisioningStatus endpoint checks. Hence, we
      # check for existence of such tenants using the /twirp/v0.TenantService/GetTenant endpoint to
      # confirm if their provisioning was completed successfully.
      response = client.connection.post("/twirp/v0.TenantService/GetTenant", payload.to_json)
      if response.success? && JSON.parse(response.body)["result"] == "Success"
        :completed
      else
        :failed
      end
    end
  rescue Faraday::Error, JSON::ParserError, NoMethodError => error
    Failbot.report(error)
  end
end
