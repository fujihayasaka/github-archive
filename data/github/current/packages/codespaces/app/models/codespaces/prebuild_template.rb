# typed: true
# frozen_string_literal: true

module Codespaces
  class PrebuildTemplate < ApplicationRecord::Domain::Codespaces
    include Instrumentation::Model
    include Codespaces::VscsTargetDependency

    self.table_name = "codespace_prebuild_templates"

    belongs_to :repository
    belongs_to :plan, class_name: "Codespaces::Plan", foreign_key: :plan_id, inverse_of: :prebuild_templates

    # rubocop:todo Rails/InverseOf
    has_one :billing_entry, -> { order(id: :desc) },
    validate: true,
    class_name: "Codespaces::PrebuildTemplateBillingEntry",
    foreign_key: :prebuild_template_guid,
    primary_key: :guid,
    strict_loading: false
    # rubocop:enable Rails/InverseOf

    belongs_to :configuration,
      class_name: "Codespaces::PrebuildConfiguration",
      foreign_key: :codespace_prebuild_configuration_id,
      inverse_of: :prebuild_templates

    validates :guid, length: { is: 36 }, allow_nil: true
    validates :name, uniqueness: true
    validates :branch, :location, :oid, :repository, presence: true
    validate :validate_plan
    validate :valid_local_target_url, if: -> { T.bind(self, PrebuildTemplate); vscs_target&.to_sym == :local }
    validate :valid_configuration?, on: :create

    before_validation :generate_name, on: :create
    after_save :ensure_billing_entry, if: -> { T.bind(self, PrebuildTemplate); guid.present? && id.present? }
    before_destroy :set_billing_entry_deleted_at, if: -> { T.bind(self, PrebuildTemplate); billing_entry.present? }

    enum :state, %i{
      pending
      provisioned
      failed
      archived
    }

    # TODO: Remove once backfill of plan is complete
    def plan
      if GitHub.flipper[:codespaces_prebuild_template_plan_backfill].enabled?(billable_owner)
        super || Codespaces::Plan.for(location: location, vscs_target: vscs_target)
      else
        Codespaces::Plan.for(location: location, vscs_target: vscs_target)
      end
    end

    def moniker
      if self.branch != self.repository&.default_branch
        "#{self.repository&.permalink}/tree/#{self.branch}"
      else
        self.repository&.permalink
      end
    end

    def self.exist_on_repo?(repository_id)
      where(repository_id: repository_id).exists?
    end

    def billable_owner
      self.repository&.owner
    end

    def matches_configuration?
      mismatched_configuration_attributes.empty?
    end

    private

    # PrebuildTemplates, like Codespaces, are both saved as codespace environments in VSCS.
    # `name` is a required attribute for the VSCS environment, and codespace names must be globally unique.
    # The `prebuild_template_` prefix & v4 random UUID are used to prevent name collisions.
    # Codespace names cannot use underscores because underscores are not allowed in url subdomains
    # and adding a prefix to PrebuildTemplate names that includes underscores ensures no name
    # collisions with `codespace` records.
    def generate_name
      self.name = "prebuild_template_#{SecureRandom.uuid}" unless name.present?
    end

    def validate_plan
      errors.add(:plan, "No plan found for location and vscs_target") unless plan.present?
    end

    def set_billing_entry_deleted_at
      Codespaces::PrebuildTemplateBillingEntry.where(prebuild_template_guid: guid).
        touch_all(:prebuild_deleted_at)
    end

    def ensure_billing_entry
      return if billing_entry&.persisted?
      self.create_billing_entry(
        billable_owner: self.billable_owner,
        prebuild_template_guid: guid,
        prebuild_template_id: id,
        prebuild_plan_name: self.plan&.name,
        prebuild_created_at: self.created_at,
        repository: repository)
    end

    def valid_local_target_url
      unless Codespaces::Vscs.valid_local_target_url?(repository: repository, vscs_target: vscs_target, vscs_target_url: vscs_target_url)
        errors.add(:vscs_target_url, "must be a valid local target URL")
      end
    end

    def mismatched_configuration_attributes
      return [] unless configuration.present?

      missmatched_attributes = []

      if configuration&.region_names.exclude?(location)
        missmatched_attributes << :location
      end

      if configuration&.branch != branch
        missmatched_attributes << :branch
      end

      if configuration&.devcontainer_path != devcontainer_path

        # Our configuration could be nil and then updated to the default path if the file exists on the repo
        # This would set the devcontainer path on the configuration, but the prebuild template would still have a nil devcontainer path
        # This is a valid state in the codespaces service, so we should not consider this a mismatch
        is_nil_template_using_default = devcontainer_path.nil? && Codespaces::DevContainer.is_default_path?(configuration&.devcontainer_path)

        if !is_nil_template_using_default
          missmatched_attributes << :devcontainer_path
        end
      end

      if configuration&.vscs_target != vscs_target
        missmatched_attributes << :vscs_target
      end

      missmatched_attributes
    end

    def valid_configuration?
      if configuration.nil?
        errors.add(:configuration, "must be present")
        return
      end

      missmatched_attributes = mismatched_configuration_attributes

      missmatched_attributes.each do |attribute|
        configuration_value = attribute == :location ? configuration&.region_names : configuration.send(attribute)
        errors.add(attribute, "must match the associated configuration: #{configuration_value}")
      end
    end

  end
end
