# typed: strict
# frozen_string_literal: true

class AddUseImmutableSubjectToOrganizationOIDCSubClaimTemplates < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Oidc)

  sig { void }
  def change
    add_column :organization_oidc_sub_claim_templates, :use_immutable_subject, :boolean, null: false, default: false
  end
end
