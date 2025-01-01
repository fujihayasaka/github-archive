# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class SecurityConfigsBannerComponent < ApplicationComponent
    extend T::Sig
    include GitHub::ResilienceMixin

    sig { returns(Organization) }; attr_reader :org
    sig { returns(T.untyped) }; attr_reader :system_arguments

    sig { params(org: Organization, system_arguments: T.untyped).void }
    def initialize(org:, **system_arguments)
      @org = org
      @system_arguments = system_arguments
    end

    sig { returns(T::Boolean) }
    def render?
      return false unless current_user
      return false if dismissed?

      true
    end

    sig { returns(T::Boolean) }
    def dismissed?
      with_database_error_fallback(fallback: true) do
        SecurityCenter::KV.store.exists(self.class.dismissal_key(user_id: current_user.id)).value!
      end
    end

    sig { params(user_id: Integer).returns(String) }
    def self.dismissal_key(user_id:)
      "security-configs-banner-component.dismissed.#{user_id}"
    end
  end
end
