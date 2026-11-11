# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      # Member is :anonymous.
      # Note: Member is not user-controlled
      class Anonymous < AuthenticationMethod
        def applicable?
          input.member == :anonymous
        end

        def process
          result.credential = "none"
          result.success!
        end
      end
    end
  end
end
