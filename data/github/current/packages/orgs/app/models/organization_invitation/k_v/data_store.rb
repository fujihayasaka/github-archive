# typed: strict
# frozen_string_literal: true

class OrganizationInvitation
  class KV
    class DataStore < ApplicationRecord::Domain::Users
      self.table_name = "org_invites_key_values"
    end
  end
end
