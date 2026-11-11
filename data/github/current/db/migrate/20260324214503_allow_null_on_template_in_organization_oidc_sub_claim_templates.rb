# typed: strict
# frozen_string_literal: true

class AllowNullOnTemplateInOrganizationOIDCSubClaimTemplates < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Oidc)

  sig { void }
  def change
    change_column_null :organization_oidc_sub_claim_templates, :template, true
  end
end
