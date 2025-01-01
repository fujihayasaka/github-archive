# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      # Member is :slumlord.
      # Note: Member is not user-controlled
      class Slumlord < AuthenticationMethod
        def applicable?
          input.member == :slumlord
        end

        def process
          result.credential = "port:svnbridge"
          result.success!
        end
      end
    end
  end
end
