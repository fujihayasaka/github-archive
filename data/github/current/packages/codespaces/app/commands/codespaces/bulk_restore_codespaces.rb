
# typed: true
# frozen_string_literal: true

module Codespaces
  class BulkRestoreCodespaces < Command

    attr_reader :user_id, :deletion_reasons

    def initialize(user_id:, deletion_reasons: nil)
      @user_id = user_id
      @deletion_reasons = deletion_reasons
    end

    def perform
      user = User.find_by(id: user_id)
      return unless user.present?

      deleted_codespaces_query = { billable_owner: user_id }

      if deletion_reasons.present?
        deleted_codespaces_query[:deletion_reason] = deletion_reasons.map { |reason| Codespace.deletion_reasons[reason.to_sym] }.compact
      end

      deleted_codespaces = Codespace.deleted.where(deleted_codespaces_query)

      deleted_codespaces.find_each do |codespace|
        begin
          Codespaces::ScheduleEnvironmentRestoration.call(codespace)
        rescue Codespaces::ScheduleEnvironmentRestoration::UnrestorableEnvironmentError
          # We don't want individual unrestorable environments to be fatal to the whole bulk restore but let's leave a
          # paper trail
          GitHub.logger.warn("Unrestorable environment", {
            "code.namespace" => "Codespaces::BulkRestoreCodespaces",
            "code.function" => "perform",
            "gh.codespaces.name" => codespace.name,
            "gh.codespaces.guid" => codespace.guid,
          })
        end
      end

      GitHub.logger.info(
        "codespaces bulk restore",
        {
          "gh.codespaces.bulk_restore_codespaces.user_id" => user_id,
          "gh.codespaces.bulk_restore_codespaces.deleted_codespaces_count" => deleted_codespaces.count,
        }
      )
    end
  end
end
