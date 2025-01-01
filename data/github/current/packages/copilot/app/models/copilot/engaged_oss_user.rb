# typed: strict
# frozen_string_literal: true

module Copilot
  class EngagedOssUser < ApplicationRecord::Copilot
    include Copilot::Metrics

    self.table_name = "copilot_engaged_oss_users"
    self.strict_loading_by_default = true

    # rubocop:todo Rails/InverseOf
    belongs_to :engaged_oss_repository, class_name: "Copilot::EngagedOssRepository", foreign_key: "repository_id", strict_loading: false
    # rubocop:enable Rails/InverseOf

    has_one :repository, through: :engaged_oss_repository, disable_joins: true
    belongs_to :user, class_name: "::User", strict_loading: false

    VALID_ROLES = T.let(%w[admin write maintain].freeze, T::Array[String])

    validates :language, presence: true
    validates :engaged_oss_repository, presence: true
    validates :role, presence: true
    validates :user, presence: true

    validates :role, inclusion: { in: VALID_ROLES }

    sig { returns(T.nilable(Integer)) }
    def to_i
      id
    end
  end
end
