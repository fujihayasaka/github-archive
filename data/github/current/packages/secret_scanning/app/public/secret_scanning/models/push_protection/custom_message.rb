# typed: strict
# frozen_string_literal: true

class SecretScanning::Models::PushProtection::CustomMessage < T::Struct
  const :owner_name, String
  const :owner_type, String
  const :message, String
end
