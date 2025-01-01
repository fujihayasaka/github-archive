# typed: true
# frozen_string_literal: true

module Orgs
  class SecuritySettingsController < Controller

    before_action :organization_admin_required
    before_action :sudo_filter, except: %i(index)
    before_action :ensure_trade_restrictions_allows_org_settings_access

    # Allow pagination above the cap of 100 for customers with 1000s
    # of ip allow list entries
    skip_before_action :cap_pagination, only: %i(index)

    javascript_bundle :settings
    stylesheet_bundle :businesses

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Billing,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Notify,
      only: [:index]

    include EnterpriseManagedUsersHelper

    def index
      respond_to do |format|
        format.html do
          if request.xhr? && GitHub.ip_allowlists_available?
            headers["Cache-Control"] = "no-cache, no-store"
            render partial: "ip_allowlist_entries/list", locals: {
              owner: this_organization,
              new_entry_path: organization_ip_allowlist_entries_path(this_organization),
            }
          else
            if this_organization.business_plus?
              view = create_view_model(
                Orgs::SecuritySettings::IndexView,
                organization: this_organization,
                business: this_organization.business,
                current_user: current_user,
                saml_provider: saml_provider,
                current_external_identity: current_external_identity(target: this_organization),
                team_sync_setup_flow: ::TeamSync::SetupFlow.new(organization: this_organization, actor: current_user)
              )
              render "orgs/security_settings/index", locals: { view: view }
            else
              view = create_view_model(
                Orgs::SecuritySettings::IndexView,
                organization: this_organization
              )
              render "orgs/security_settings/index", locals: { view: view }
            end
          end
        end
      end
    end

    private

    memoize def saml_provider
      if flash[:saml_test_result]
        provider = Organization::SamlProviderTestSettings.most_recent_for(
          user: current_user,
          org: this_organization,
          result: flash[:saml_test_result],
        )
        ActiveRecord::Base.connected_to(role: :writing) do
          provider.save!
        end
        provider
      else
        this_organization.saml_provider || this_organization.build_saml_provider
      end
    end
  end
end
