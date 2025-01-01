# typed: strict
# frozen_string_literal: true

class OauthApplicationDeleteJob < ApplicationJob
  extend T::Sig

  queue_as :oauth_application_delete

  locked_by timeout: 1.hour, key: ->(job) {
    job.arguments[0] # oauth_application_id
  }

  discard_on ActiveRecord::RecordNotFound

  retry_on_dirty_exit

  # Resolving the tenant context here mainly serves to ensure that the
  # associated dependent records that are deleted synchronously are
  # deleted in the correct tenant context.
  resolve_tenant_context do |oauth_application_id|
    oauth_application = OauthApplication.find_by(id: oauth_application_id)

    if oauth_application.present?
      user = T.must(oauth_application.user)
      user.is_a?(Organization) ? user.business : user.enterprise_managed_business
    end
  end

  sig { params(oauth_application_id: Integer).void }
  def perform(oauth_application_id)
    app = OauthApplication.find_by(id: oauth_application_id)
    return unless app.present?

    GitHub.dogstats.distribution_time("oauth_application", tags: ["action:delete", "via:job"]) do
      with_write { app.destroy }
    end
  end
end
