# typed: true
# frozen_string_literal: true

module Organization::ProgrammaticAccessGrantDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ApplicationRecord::Base))

    # Do not use this relation directly! This is to help Rails build
    # the AR relationships accordingly.
    #
    # Please use: ProgrammaticAccessGrant.with_target(organization)
    has_many :organization_programmatic_access_grants, inverse_of: :target, dependent: :destroy
    has_many :organization_programmatic_access_grant_requests, inverse_of: :target, dependent: :destroy
  end
end
