# typed: true
# frozen_string_literal: true

class StafftoolsToggleNetworkTokenScanningJob < ApplicationJob
  queue_as :stafftools_toggle_scanning
  retry_on_dirty_exit

  around_perform :use_read_replicas

  discard_on ActiveRecord::RecordNotFound do |_, error|
    Failbot.report(error)
  end

  def perform(repository_id, user_id, enable)
    parent_repository = Repository.find_by(id: repository_id)
    user = User.find(user_id)
    return false unless parent_repository && user
    parent_repository.descendants.each do |repository|
      service_manager = SecurityProduct::ServiceManager.new(repository)
      if enable
        use_primary { service_manager.toggle_services(user, services_to_enable: [[:token_scanning, { force?: true, use_staff_key: true, update_rest_of_network?: false, use_network_flag?: true }]]) }
      else
        use_primary { service_manager.toggle_services(user, services_to_disable: [[:token_scanning, { force?: true, use_staff_key: true, update_rest_of_network?: false, use_network_flag?: true }]]) }
      end
    end
  end

  def use_read_replicas
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end

  def use_primary
    ActiveRecord::Base.connected_to(role: :writing) do
      yield
    end
  end
end
