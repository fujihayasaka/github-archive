# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaInterface
    sig do
      params(
        current_user: User,
        permanent_name: String,
        friendly_name: String
      ).void
    end
    def self.notify_friendly_name_change(current_user, permanent_name, friendly_name)
      client = SparkRuntime::AcaManagementClient.new(current_user, permanent_name)
      client.patch_app({ CustomName: friendly_name })
    end
  end
end
