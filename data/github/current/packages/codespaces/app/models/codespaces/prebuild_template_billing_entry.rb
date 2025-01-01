# typed: true
# frozen_string_literal: true

module Codespaces
  # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  class PrebuildTemplateBillingEntry < ApplicationRecord::Domain::Codespaces
    # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
    include Instrumentation::Model

    self.table_name = "codespace_prebuild_template_billing_entries"
    self.strict_loading_by_default = true

    # rubocop:todo Rails/InverseOf
    belongs_to :prebuild_template, foreign_key: :prebuild_template_guid, primary_key: :guid, strict_loading: false
    # rubocop:enable Rails/InverseOf
    belongs_to :billable_owner, polymorphic: true, strict_loading: false
    belongs_to :repository, class_name: "::Repository", strict_loading: false

    validates :billable_owner, :prebuild_template_id, :prebuild_template_guid, presence: true

    before_validation :ensure_prebuild_template_id
    before_validation :ensure_prebuild_plan_name
    before_validation :ensure_prebuild_created_at

    def ensure_prebuild_template_id
      template_id = prebuild_template&.id
      return if prebuild_template_id.present? || template_id.blank?

      self.prebuild_template_id = template_id
    end

    def ensure_prebuild_plan_name
      return if prebuild_plan_name.present?
      self.prebuild_plan_name = prebuild_template&.plan&.name
    end

    def ensure_prebuild_created_at
      template_created_at = prebuild_template&.created_at
      return if prebuild_created_at.present? || template_created_at.blank?

      self.prebuild_created_at = template_created_at
    end

    def self.latest(prebuild_template_guid)
      where(prebuild_template_guid: prebuild_template_guid).last!
    end

    def self.latest_created_before(prebuild_template_guid, created_before)
      where(prebuild_template_guid: prebuild_template_guid).where("created_at <= ?", created_before).last
    end

    def copilot_workspace_id
      nil
    end

    def for_prebuild?
      true
    end

    def for_codespace?
      false
    end

    def for_copilot_workspace?
      false
    end

    def for_workspace_editor?
      false
    end
  end
end
