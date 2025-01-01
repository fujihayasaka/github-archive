# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module SetZuoraBackgroundClient
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ActiveJob::Base }

  included do
    T.bind(self, T.class_of(ActiveJob::Base))

    around_perform do |_job, block|
      previous_client = GitHub.zuorest_client
      if GitHub.billing_enabled?
        GitHub.zuorest_client = GitHub.zuorest_background_worker_client
        Zuorest::Model::Base.zuora_rest_client = GitHub.zuorest_client
        Failbot.push(zuorest_background_worker_client: true)
      end

      begin
        block.call
      ensure
        if GitHub.billing_enabled?
          GitHub.zuorest_client = previous_client
          Zuorest::Model::Base.zuora_rest_client = GitHub.zuorest_client
        end
      end
    end
  end
end
