# typed: true
# frozen_string_literal: true

require "active_model"

module KvMigration
  module Generator
    class OptionValidator
      include ActiveModel::Model

      attr_accessor :ghes_migration, :version, :migration, :run, :transition, :key_patterns, :service, :domain, :owner, :ownership_file_path, :cluster

      validate :validate_ghes_migration_with_version
      validate :validate_ghes_exclusivity
      validate :validate_transition
      validate :validate_migration
      validate :validate_transition_and_migration_exclusivity
      validate :validate_owner
      validate :validate_minimal_options

      def validate_ghes_migration_with_version
        if ghes_migration.present? && version.blank?
          errors.add(:version, "must be provided when ghes_migration is set")
        end
      end

      def validate_ghes_exclusivity
        if ghes_migration.present? && (migration.present? || transition.present? || service.present? || domain.present?)
          errors.add(:ghes_migration, "cannot be provided with any other option")
        end
      end

      def validate_transition
        if transition.present? && (service.blank? || domain.blank?)
          errors.add(:transition, "must be provided with service and domain")
        end
      end

      def validate_migration
        if migration.present? && (service.blank? || domain.blank?)
          errors.add(:migration, "must be provided with service and domain")
        end
      end

      def validate_transition_and_migration_exclusivity
        if transition.present? && migration.present?
          errors.add(:transition, "and migration cannot be provided together")
        end
      end

      def validate_owner
        return if owner.blank?

        ownership_file_path ||= GitHub::Serviceowners::Tableowners::OWNERSHIP_YAML_PATH
        ownership_yaml = YAML.load_file(ownership_file_path)
        valid_owners = ownership_yaml["ownership"]
          .each_with_object(Set.new) { |item, set| set << item["name"] if item["name"] }
          .freeze

        unless valid_owners.include?(owner)
          errors.add(:owner, "must be in the list of valid owners")
        end
      end

      def validate_minimal_options
        if ghes_migration.blank? && migration.blank? && transition.blank?
          errors.add(:base, "must provide either ghes_migration, migration, or transition")
        end
      end
    end
  end
end
