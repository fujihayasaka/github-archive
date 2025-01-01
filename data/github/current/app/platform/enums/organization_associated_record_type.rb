# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationAssociatedRecordType < Platform::Enums::Base
      description "The possible organization-associated record types."
      visibility :internal

      value "GIST", "Gist.", value: :gists
      value "INVITATION", "Organization invitation.", value: :invitations
      value "REPO", "Repository.", value: :repositories
    end
  end
end
