
# typed: true
# frozen_string_literal: true

module Codespaces
  class ProcessPlanChange < Command

    attr_reader :user_id, :old_plan_name, :new_plan_name

    def initialize(user_id:, old_plan_name:, new_plan_name:)
      @user_id = user_id
      @old_plan_name = old_plan_name
      @new_plan_name = new_plan_name
    end

    def perform
      owner = User.find_by(id: user_id)
      return unless owner.present?

      if downgrading_to_free? && owner.organization?
        Codespace.where(billable_owner: owner.id).in_batches do |codespaces_batch|
          CodespacesProcessSystemEventJob.perform_later(codespaces: codespaces_batch.to_a, transfer_billable_owner: false, deletion_reason: Codespace.deletion_reasons[:org_downgrade])
        end
        deletion_date = Codespaces::ProcessSystemEvent::CLEAN_UP_INACCESSIBLE_CODESPACE_WAITING_PERIOD.from_now
        Codespaces::OrgDowngradeCleanupNotificationJob.perform_later(owner_id: owner.id, deletion_date: deletion_date)
      end
    end

    private

    def downgrading_to_free?
      GitHub::Plan.free_names.include?(new_plan_name) && !GitHub::Plan.free_names.include?(old_plan_name)
    end
  end
end
