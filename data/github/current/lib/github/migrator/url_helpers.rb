# typed: false
# frozen_string_literal: true

module GitHub
  class Migrator
    module UrlHelpers
      include TarUtils

      # Internal: Build instance of UrlTranslator with correct from template.
      def url_translator
        @url_translator ||= begin
          templates = archive_url_templates
          if templates
            UrlTranslator.new(from: templates)
          else
            UrlTranslator.new
          end
        end
      end

      def source_url_templates
        url_translator.from
      end

      # Internal: Fetch url template based on migratable resource model type
      def model_url_template(model_type, attributes)
        # Certain models have mulitple templates based on if they are tied to an issue or pull request
        # Extracted the nested template based on the existance of a parent issue or pull_request key in attributes
        if %w(issue_comment issue_event).include?(model_type)
          issue_or_pull_request_key = (attributes.keys & %w(issue pull_request)).first
          source_url_templates[model_type][issue_or_pull_request_key]
        else
          source_url_templates[model_type]
        end
      end

      # Internal: Extract urls.json from archive or default to DefaultUrlTemplates.
      #
      # Returns a Hash.
      def archive_url_templates
        @archive_url_templates ||= begin
          templates = DefaultUrlTemplates

          read_from_archive("urls.json") do |file|
            templates = GitHub::JSON.parse(file.read)
          end

          templates.tap do |t|
            key = "migrationUrlTemplates-#{current_migration.guid}"

            ActiveRecord::Base.connected_to(role: :writing) do
              GitHub::Migrator::KV.store.set(key, t.to_json)
            end
          end
        end
      end
    end
  end
end
