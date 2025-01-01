# typed: true
# frozen_string_literal: true

module ScopedIntegrationInstallable
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Kernel }
  requires_ancestor { ActiveRecord::Base }

  # Public: extend the expires_at timestamp of this record and its associated
  # permissions to prevent it being cleaned up by pt-archiver.
  def extend_expires_at(timestamp, async: false, entry_point:)
    T.bind(self, T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    if async
      # TODO: think about how to propagate the entry point metadata to the job,
      # for now we keep passing the tag_name identifier.
      entry_point = entry_point.to_sym if entry_point.present?
      ScopedIntegrationInstallableExpirationExtensionJob.perform_later(self, timestamp, entry_point: entry_point)
    else
      extend_expires_at!(timestamp, entry_point: entry_point)
    end
  end

  def extend_expires_at!(timestamp, entry_point:)
    T.bind(self, T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    ability_ids = abilities.pluck(:id)

    # If the new expiry timestamp is equivalent to the existing expiry, there is no need to update the database.
    if timestamp.to_i == expires_at.to_i
      skip_expires_at_extension = GitHub.flipper[:skip_extending_equivalent_expires_at].enabled?

      if GitHub.flipper[:measure_noop_extending_equivalent_expires_at].enabled?
        tags = ["entry_point:#{entry_point.to_sym}"]
        tags << "skipped:#{skip_expires_at_extension.inspect}"
        permissions_count_range =
          case ability_ids.count
          when 0 then "0"
          when 1..9 then "1-9"
          when 10..99 then "10-99"
          when 100..999 then "100-999"
          else "1000+"
          end
        tags << "permissions_count_range:#{permissions_count_range}"
        GitHub.dogstats.distribution("permissions_service.extend_expires_at.noop", 1, tags: tags)
        GitHub.dogstats.distribution("permissions_service.extend_expires_at.noop_permissions_written", ability_ids.count, tags: tags)
      end

      # if feature flag is enabled, we can skip updating the expiry unnecessarily
      if skip_expires_at_extension
        # we do still want to register that the token was extended in the audit logs so we need to instrument here
        instrument_extend_expires_at
        return
      end
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      ::Permissions::Service.update_expires_at_for_permissions(
        permission_ids: ability_ids,
        timestamp: timestamp,
        entry_point: entry_point,
      )

      update!(expires_at: timestamp)
      instrument_extend_expires_at
    end
  end

  def expired?
    T.bind(self, T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    expires_at.present? && Time.now.to_i > expires_at.to_i
  end

  private

  def instrument_extend_expires_at
    raise NotImplementedError
  end
end
