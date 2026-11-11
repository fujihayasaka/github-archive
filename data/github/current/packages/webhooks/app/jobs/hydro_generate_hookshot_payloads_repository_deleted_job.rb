# typed: true
# frozen_string_literal: true

class HydroGenerateHookshotPayloadsRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_generate_hookshot_payloads_repository_deleted

  def perform
    with_write do
      if deleter
        event = Hook::Event::RepositoryEvent.new repository_id: repository.id, actor_id: deleter.id, action: :deleted, triggered_at: Time.now
        delivery_system = Hook::DeliverySystem.new(event)
        delivery_system.generate_hookshot_payloads
        delivery_system.deliver_later
      end
    end
  end

  memoize def deleter
    return nil if message[:actor_id].blank?
    User.find_by(id: message[:actor_id][:value])
  end
end
