# typed: true
# frozen_string_literal: true

module User::SecurityCenterDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(::User))
    has_many :repository_security_center_configs, foreign_key: "owner_id", inverse_of: :owner
    has_many :repository_security_center_statuses, foreign_key: "owner_id", inverse_of: :owner
  end
end
