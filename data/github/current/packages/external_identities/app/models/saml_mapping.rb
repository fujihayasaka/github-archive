# typed: true
# frozen_string_literal: true

class SamlMapping < ApplicationRecord::Domain::Users
  class NameIdMismatch < StandardError; end

  include GitHub::Validations
  belongs_to :user
  validates_presence_of :name_id, :name_id_format
  validates_uniqueness_of :name_id, case_sensitive: false
  validates :name_id, unicode3: true
  validates :name_id_format, unicode3: true

  # Find a SamlMapping entry by nameid and name_id_format
  def self.by_name_id_and_name_id_format(name_id, name_id_format)
    ensure_exact_name_id(where(name_id: name_id, name_id_format: name_id_format).first, name_id)
  end

  def self.by_name_id(name_id)
    ensure_exact_name_id(find_by(name_id: name_id), name_id)
  end

  def self.ensure_exact_name_id(mapping, name_id)
    return mapping unless GitHub.single_tenant_enterprise?

    # MySQL's collation can match a different NameID; do not let it reach another lookup fallback.
    if mapping && mapping.name_id != name_id
      GitHub::Authentication.logger.error(
        "SAML failure - NameID mismatch",
        "gh.saml_mapping.id" => mapping.id,
        "gh.user.id" => mapping.user_id,
      )
      raise NameIdMismatch, "SAML NameID does not exactly match the stored mapping"
    end

    mapping
  end
  private_class_method :ensure_exact_name_id

  def migrate_mapping!(new_name_id, login)
    SamlMapping.transaction do
      if need_migration?(new_name_id, login)
        update_attribute(:name_id, new_name_id)
      end
    end
  end

  def need_migration?(new_name_id, login)
    login.downcase == name_id.downcase && name_id.downcase != new_name_id.downcase
  end

  def has_persistent_name_id_format?
    name_id_format == "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent"
  end
end
