# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module React
      class BlankslatePayloadBuilder < BasePayloadBuilder
        sig { params(type: BlankslateType).returns(T::Hash[T.untyped, T.untyped]) }
        def blankslate_payload(type)
          payload = {
            blankslate_type: type.serialize,
            repository: {
              name: @repo.name,
              owner_display_login: @repo.owner_display_login,
            },
            adminable: @repo.adminable_by?(@user),
            help_url: GitHub.help_url
          }

          if GitHub.enterprise?
            payload.merge!({
              enterprise_contact_path: UrlHelpers.contact_path,
            })
          end

          payload
        end
      end
    end
  end
end
