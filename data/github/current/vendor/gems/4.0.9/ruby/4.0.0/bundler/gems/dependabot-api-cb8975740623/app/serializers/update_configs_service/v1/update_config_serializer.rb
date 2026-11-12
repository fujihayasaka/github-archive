# frozen_string_literal: true

module UpdateConfigsService
  module V1
    class UpdateConfigSerializer < ActiveModel::Serializer
      CONFIG_FILE_VERSION = 2

      attributes :id,
                 :last_full_update_run,
                 :monitored_manifest_files,
                 :multi_ecosystem_config_id,
                 :package_ecosystem,
                 :serialized_config_file_yml,
                 :serialized_config_file_defaults_yml,
                 :target_branch

      delegate :multi_ecosystem_config_id, to: :object

      def last_full_update_run
        return unless object.last_scheduled_job

        UpdateConfigsService::V1::UpdateJobStatusSerializer.
          new(object.last_scheduled_job).to_h
      end

      def monitored_manifest_files
        return if object.monitored_files.blank?

        object.monitored_files.map { |file_path| { path: file_path } }
      end

      # TODO: Implement an ecosystem support level mapping
      def package_ecosystem
        UpdateConfigsService::V1::PackageEcosystemSerializer.new(object.package_manager, scope).to_h
      end

      def serialized_config_file_yml
        {
          "version" => CONFIG_FILE_VERSION,
          "updates" => [
            serialized_config_file.transform_keys(&method(:kebab_case)),
          ],
        }.to_yaml
      end

      def serialized_config_file_defaults_yml
        serialized_config_file_with_defaults.
          reject { |k, _| serialized_config_file.key?(k) }.
          transform_keys(&method(:kebab_case)).
          to_yaml
      end

      private

      def serialized_config_file
        @serialized_config_file ||=
          ConfigFiles::UpdateConfigSerializer.
          new(object).
          to_h.sort.to_h
      end

      def serialized_config_file_with_defaults
        @serialized_config_file_with_defaults ||=
          ConfigFiles::UpdateConfigSerializer.
          new(object, include_defaults: true).
          to_h.sort.to_h
      end

      def kebab_case(str)
        str.to_s.dasherize
      end
    end
  end
end
