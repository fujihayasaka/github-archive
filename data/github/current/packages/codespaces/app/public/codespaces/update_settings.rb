# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class UpdateSettings < Command
    include Codespaces::RateLimitable
    attr_reader :codespace, :data
    class FailedToUpdate < StandardError; end
    class CodespacesStillProvisioningError < StandardError; end

    def initialize(codespace:, **data)
      @codespace = codespace
      @data = data
    end

    def perform
      with_rate_limiting(@codespace.owner) do
        codespace.ensure_no_blocking_pending_async_operation!
        update!(**data)
      end
    end

    def update!(**data)
      update_display_name!
      update_retention_period!

      sku_name = data[:sku_name]
      update_sku!(sku_name, codespace) if sku_name

      update_recent_folders!
    end

    private

    def update_sku!(sku_name, codespace)
      raise CodespacesStillProvisioningError.new("Codespace machine type cannot be updated while codespace is still provisioning") if codespace.provisioning?
      if Codespaces::Skus.valid_sku_for_existing_codespace?(sku_name, codespace)
        # Check storage sizes
        old_sku = Codespaces::Skus::sku_by_name(codespace.sku_name)
        new_sku = Codespaces::Skus::sku_by_name(sku_name)
        if old_sku.storage_in_gb == new_sku.storage_in_gb
          # We just need to update our DB, new SKU name will be sent on the next resume
          # and VSCS knows how to handle that
          codespace.update!(sku_name: sku_name)

          GitHub.instrument("codespaces.change_sku",
            codespace_id: codespace.id,
            environment_id: codespace.guid,
            new_sku: new_sku.name.to_s,
            old_sku: old_sku.name.to_s,
            plan_id: codespace.plan_id,
            user: codespace.owner,
            repo: codespace.repository,
          )
        else
          op = Codespaces::AsyncOperation.create(
            codespace: codespace,
            operation: :update_storage,
          )
          CodespacesResizeStorageJob.perform_later(codespace_id: codespace.id, new_sku_name: sku_name, operation: op)
        end
      else
        raise FailedToUpdate, "Invalid machine for user"
      end
    rescue ActiveRecord::ActiveRecordError => e
      raise FailedToUpdate.new(e)
    end

    def update_display_name!
      return unless new_display_name = data[:display_name]

      codespace.update!(display_name: new_display_name)
    rescue ActiveRecord::ActiveRecordError => e
      raise FailedToUpdate.new(e)
    end

    def update_retention_period!
      if data.key?(:retention_period_minutes)
        codespace.update!(retention_period_minutes: retention_period || Codespace::MAX_RETENTION_PERIOD)
      end
    rescue ActiveRecord::ActiveRecordError => e
      raise FailedToUpdate.new(e)
    end

    def retention_period
      return unless data.key?(:retention_period_minutes)

      Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
        user: codespace.owner,
        repository: codespace.repository,
        billable_owner: codespace.billable_owner,
        requested_retention_period_minutes: data.fetch(:retention_period_minutes)
      )
    end

    def update_recent_folders!
      return unless recent_folders = data[:recent_folders]

      client = Codespaces::VscsClient.for_codespace(codespace)
      client.update_recent_folders(codespace.guid, recent_folders)
      codespace.reload

      rescue ArgumentError => e
        raise FailedToUpdate.new(e)
    end
  end
end
