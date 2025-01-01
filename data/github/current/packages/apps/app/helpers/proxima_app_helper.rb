# typed: strict
# frozen_string_literal: true

# This module contains helper methods for syncing apps with Proxima
module ProximaAppHelper
  extend T::Sig
  include Kernel

  FIRST_PARTY_TYPE = T.let("first".freeze, String)
  THIRD_PARTY_TYPE = T.let("third".freeze, String)

  InvalidGlobalRelayId = Class.new(StandardError)

  sig { params(global_relay_id: String).returns(T.nilable(T.any(OauthApplication, Integration))) }
  def app_from_global_id(global_relay_id)
    klass, id = Platform::Helpers::NodeIdentification.from_global_id(global_relay_id)

    klass = case klass
    when "OauthApplication"
      OauthApplication
    when "App"
      Integration
    else
      raise InvalidGlobalRelayId, "Invalid global relay id: #{global_relay_id}. #{klass} is not a valid type."
    end

    klass.find_by(id: id)
  end
end
