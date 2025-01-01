# typed: true
# frozen_string_literal: true

# Defines the attributes that should be equivalent between SAML and SCIM
module Platform::Provisioning
  class IdentityMapping

    def saml_attribute
      if GitHub.global_business&.enterprise_server_scim_enabled? && GitHub.saml_username_attr
        GitHub.saml_username_attr
      else
        [Platform::Provisioning::SamlUserData::NAME_ID] + Platform::Provisioning::SamlUserData::DEFAULT_USER_NAME_ATTRIBUTE
      end
    end

    def scim_attribute
      Platform::Provisioning::ScimUserData::DEFAULT_ATTRIBUTE_MAPPINGS[:user_name]
    end

    def saml_external_id_attribute
      Platform::Provisioning::SamlUserData::DEFAULT_ATTRIBUTE_MAPPINGS[:external_id]
    end

    def scim_external_id_attribute
      Platform::Provisioning::ScimUserData::DEFAULT_ATTRIBUTE_MAPPINGS[:external_id]
    end

    def identifier_attributes
      [scim_attribute] + Array(saml_attribute)
    end

    def external_id_attributes
      [scim_external_id_attribute] + Array(saml_external_id_attribute)
    end

    # Look up the identifier value from the given Platform::Provisioning::UserData
    # Prefers the scim_attribute
    def value_from_user_data(user_data)
      value   = user_data.fetch(scim_attribute, {})["value"]
      value ||= user_data.fetch(saml_attribute, {})["value"]
      value
    end
  end
end
