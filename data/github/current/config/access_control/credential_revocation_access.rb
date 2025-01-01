# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :submit_credentials_for_revocation do |access|
    access.allow :everyone
  end
end
