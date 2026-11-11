# typed: strict
# frozen_string_literal: true

module Notifyd
  module Settings
    class MuteSetting < T::Struct
      const :muted, T::Boolean
      const :created_at, T.nilable(Integer)
    end
  end
end
