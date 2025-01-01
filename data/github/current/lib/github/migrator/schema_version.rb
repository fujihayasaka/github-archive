# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    # Handles questions around "will it work?" related to schema versions.
    #
    # The schema version for exports should be as low as possible, so that
    # as many destinations as possible can import it.
    class SchemaVersion
      VERSIONS = [

        # The first version of gh-migrator.
        INITIAL_RELEASE = "1.0.0".freeze,

        # Correctly includes wikis.
        WIKI = "1.0.1".freeze,

        # The archive includes attachments.
        ATTACHABLE = "1.1.0".freeze,

        # The archive may include urls.json for UrlTranslator.
        URL_TRANSLATION = "1.2.0".freeze,

      ].freeze

      # Public: Does this version of gh-migrator know what to do with an archive with `version`?
      def can_import?(version)
        VERSIONS.include?(version)
      end

      # Public: Can this version of gh-migrator translate urls for the migration
      # archive schema version?
      def can_translate_urls?(version)
        version == URL_TRANSLATION
      end

      # Public: Get the schema version for the given migration.
      def for_export(migration)
        if migration.where(model_type: "attachment").any?
          ATTACHABLE
        else
          WIKI
        end
      end
    end
  end
end
