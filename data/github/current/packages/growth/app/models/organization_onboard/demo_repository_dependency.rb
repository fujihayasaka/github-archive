# typed: true
# frozen_string_literal: true

module OrganizationOnboard::DemoRepositoryDependency
  extend ActiveSupport::Concern

  included do
    T.unsafe(self).has_one :demo_repository, class_name: "OrganizationOnboard::DemoRepository", dependent: :destroy
  end
end
