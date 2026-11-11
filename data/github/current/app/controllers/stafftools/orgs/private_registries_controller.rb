# typed: true
# frozen_string_literal: true

class Stafftools::Orgs::PrivateRegistriesController < StafftoolsController
  include Secrets::Helper

  before_action :dotcom_only
  before_action :ensure_user_exists
  before_action :ensure_org_not_user

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    configurations = PrivateRegistry::Configuration.for_organization(this_organization)
    secrets = secrets_for(this_organization, app: private_registry_secrets_app)

    render "stafftools/organizations/private_registries/index",
      layout: "layouts/stafftools/organization/content",
      locals: {
        organization: this_organization,
        configurations: configurations,
        secrets: secrets,
      }
  end

  private

  memoize def private_registry_secrets_app
    Apps::Privileged.integration(:private_registry_secrets)
  end

  def this_organization
    this_user
  end

  # Private registries are not supported on enterprise yet.
  def dotcom_only
    render_404 if GitHub.enterprise?
  end
end
