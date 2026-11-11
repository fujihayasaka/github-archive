# typed: false
# frozen_string_literal: true

module PjaxContentPolicy
  extend ActiveSupport::Concern

  include ActionsContentPolicy

  included do
    before_action :add_dreamlifter_csp_exceptions
    before_action :add_s3_storage_csp_exceptions
  end

  def add_s3_storage_csp_exceptions
    return if GitHub.multi_tenant_enterprise?

    SecureHeaders.append_content_security_policy_directives(
      request,
      connect_src: [
        # Used by edit_repositories#options (Settings tab on repo page)
        RepositoryImage.storage_s3_hostname,
        # Used by releases#index/new/edit
        ReleaseAsset.storage_s3_new_bucket_host,
      ],
    )
  end
end
