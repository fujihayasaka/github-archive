# typed: strict
# frozen_string_literal: true

class Organizations::CredentialAuthorizations::AvatarComponent < ApplicationComponent
  sig { params(org: Organization).void }
  def initialize(org)
    @org = org
  end
end
