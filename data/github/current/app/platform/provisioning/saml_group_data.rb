# typed: true
# frozen_string_literal: true

module Platform
  module Provisioning
    class SamlGroupData < UserData
      user_data_reader name_id: Platform::Provisioning::SamlUserData::NAME_ID

      def self.load(group_name)
        self.new.tap do |user_data|
          user_data.append Platform::Provisioning::SamlUserData::NAME_ID, group_name,
                           "Format" => "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
        end
      end
    end
  end
end
