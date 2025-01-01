# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Serializers
  class SendgridData < ActiveJob::Serializers::ObjectSerializer
    def serialize(data)
      super(email: data.email, display_login: data.display_login, unsub_url: data.unsub_url)
    end

    def deserialize(hash)
      Nurture::SendgridData.new(hash[:email], hash[:display_login], hash[:unsub_url])
    end

    private

    def klass
      Nurture::SendgridData
    end
  end
end
