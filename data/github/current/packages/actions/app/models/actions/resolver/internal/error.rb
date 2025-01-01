# typed: true
# frozen_string_literal: true

class Actions::Resolver::Internal::Error < T::Struct

  prop :requested_name, String
  prop :ref, String

  prop :msg, String
end
