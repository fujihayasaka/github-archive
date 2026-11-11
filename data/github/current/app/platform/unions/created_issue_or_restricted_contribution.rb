# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CreatedIssueOrRestrictedContribution < Platform::Unions::Base

      description "Represents either a issue the viewer can access or a restricted contribution."

      possible_types Objects::CreatedIssueContribution, Objects::RestrictedContribution
    end
  end
end
