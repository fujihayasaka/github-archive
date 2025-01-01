# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Serializers
  class SendgridData < ActiveJob::Serializers::ObjectSerializer
    def serialize(data)
      super(email: data.email, display_login: data.display_login, user_id: data.user_id, unsub_url: data.unsub_url)
    end

    def deserialize(hash)
      Nurture::SendgridData.new(hash[:email], hash[:display_login], hash[:user_id], hash[:unsub_url])
    end

    private

    def klass
      Nurture::SendgridData
    end
  end
end
