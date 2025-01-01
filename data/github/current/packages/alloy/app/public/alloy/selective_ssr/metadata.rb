# typed: strict
# frozen_string_literal: true

module Alloy
  class SelectiveSsr
    class Metadata < T::Struct
      const :logged_in, T::Boolean
      const :robot, T::Boolean
      const :mobile, T::Boolean
      const :spammy, T::Boolean
      const :user_agent, String
      const :cpu_bucket, String
      const :override, T.nilable(T::Boolean)
    end
  end
end
