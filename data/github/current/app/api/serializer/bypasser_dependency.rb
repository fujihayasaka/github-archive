# typed: strict
# frozen_string_literal: true

module Api::Serializer::BypasserDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  sig { params(bypasser: SecretScanning::Models::Bypasser).returns(T::Hash[Symbol, T.untyped]) }
  def bypasser_hash(bypasser)
    h = {
      reviewer_id: bypasser.reviewer_id,
      reviewer_type: bypasser.reviewer_type,
      mode: bypasser.mode,
    }
    if bypasser.security_configuration_id.present?
      h[:security_configuration_id] = bypasser.security_configuration_id
    end
    h
  end
end
