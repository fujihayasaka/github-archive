# typed: strict
# frozen_string_literal: true

module CheckSuites
  module Public
    extend T::Sig

    # Checks if a push contains options to skip checks
    sig { params(push: Repositories::IPush).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def self.skip_checks_for_push?(push:)
      begin
        push.commits.last&.skip_checks&.downcase == "true"
      rescue GitRPC::ObjectMissing
        false
      end
    end

    # Checks if a push contains options to request checks
    sig { params(push: Repositories::IPush).returns(T::Boolean).checked(:always).on_failure(:raise) }
    def self.request_checks_for_push?(push:)
      GitHub.tracer.in_span("CheckSuites::Public.request_checks_for_push?", kind: :internal) do
        begin
          push.commits.last&.request_checks&.downcase == "true"
        rescue GitRPC::ObjectMissing
          false
        end
      end
    end
  end
end
