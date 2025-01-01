# typed: true
# frozen_string_literal: true

module Codespaces
  class Plan < ApplicationRecord::Domain::Codespaces
    # This is a known-good plan name that we can use for billing purposes in for_current_tenant! on dotcom.
    # Other tenants will fall back on older logic that uses the newest plan. This gives us a temporary fix
    # while we work on new region rollout but should be no longer needed once https://github.com/github/codespaces/issues/13813
    # is resolved.
    STABLE_DOTCOM_PLAN_NAME = "plan-944d2d48-e8b0-47d6-9581-4a015fb7de13"

    include Instrumentation::Model
    include GitHub::Validations

    class PlanNotFoundForLocation < StandardError; end
    class PlanNotFoundForTenant < StandardError; end

    MAX_NAME_LENGTH = 90
    DEFAULT_RESOURCE_PROVIDER = "Microsoft.Codespaces"

    self.table_name = "workspace_plans"
    self.strict_loading_by_default = true

    # rubocop:todo Rails/InverseOf
    has_many :codespaces,
             foreign_key: :plan_id,
             dependent: :delete_all

    has_many :prebuild_templates,
             foreign_key: :plan_id,
             dependent: :delete_all,
             inverse_of: :plan

    belongs_to :business

    validates :name, length: { in: 1..MAX_NAME_LENGTH }, unicode3: true
    validates :name, uniqueness: true, if: -> { T.bind(self, Plan); errors[:name].blank? }
    validates :vscs_target, presence: true
    validates :location, presence: true
    validates :vscs_target, inclusion: Codespaces::Vscs.targets
    validates :subscription, length: { is: 36 }
    validates_uniqueness_of :vscs_target, scope: [:business_id, :location], on: :create

    before_validation :generate_name, on: :create
    before_validation :set_subscription, on: :create

    scope :with_default_resource_provider, -> { where(resource_provider: DEFAULT_RESOURCE_PROVIDER) }
    scope :with_legacy_resource_provider, -> { where.not(resource_provider: DEFAULT_RESOURCE_PROVIDER) }

    def vscs_target_config
      Codespaces::Vscs.config_for_target(vscs_target)
    end

    # Public: Returns the VSCS target for this plan as a Symbol.
    #
    # Returns a Symbol or nil if no VSCS target specified.
    def vscs_target
      super.presence&.to_sym
    end

    def event_prefix
      "codespaces_plan"
    end

    def event_payload
      {
        plan_id: id,
        name: name,
      }
    end

    def self.tenant_id
      GitHub::CurrentTenant.get&.id
    end

    def self.for_current_tenant!(vscs_target:)
      plan = if GitHub.flipper[:codespaces_new_plan_for_current_tenant].enabled?
        for_current_tenant(vscs_target: vscs_target).find_by(name: STABLE_DOTCOM_PLAN_NAME) || for_current_tenant(vscs_target: vscs_target).last
      else
        for_current_tenant(vscs_target: vscs_target).last
      end
      return plan if plan.present?

      error = report_error(
        message: "No plan found for tenant_id #{tenant_id} and vscs_target #{vscs_target}",
        error: PlanNotFoundForTenant,
        attrs: {
          vscs_target: vscs_target,
          tenant_id: tenant_id
        }
      )

      raise error
    end

    def self.for_current_tenant(vscs_target:)
      where(vscs_target: vscs_target, business_id: tenant_id)
    end

    def self.for!(vscs_target:, location:, error_reporter: Codespaces::ErrorReporter.new)
      plan = Plan.for(vscs_target: vscs_target, location: location)
      return plan if plan

      error = report_error(
        message: "No location #{location} for vscs_target #{vscs_target} and tenant_id #{tenant_id}",
        error: PlanNotFoundForLocation,
        attrs: {
          vscs_target: vscs_target,
          tenant_id: tenant_id,
          location: location
        },
        error_reporter: error_reporter
      )

      raise error
    end

    def self.report_error(message:, error:, attrs: {}, error_reporter: Codespaces::ErrorReporter.new)
      error = error.new(message)
      error_reporter.push(**attrs)

      error_reporter.report(error)

      error
    end

    def self.for(vscs_target:, location:)
      where(vscs_target: vscs_target, location: location, business_id: tenant_id).last
    end

    private

    def generate_name
      self.name = self.name.presence || "plan-#{SecureRandom.uuid}"
    end

    def set_subscription
      self.subscription = self.subscription.presence || GitHub.codespaces_canonical_subscription
    end
  end
end
