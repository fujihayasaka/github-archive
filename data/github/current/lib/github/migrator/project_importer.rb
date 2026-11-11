# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ProjectImporter < GitHub::Migrator::Importer
      def import(attributes, options = {})
        project = create_project!(attributes)
        merge(attributes, project)
      end

      def merge(attributes, project)
        import_columns_and_cards!(
          project:       project,
          column_hashes: attributes["columns"],
        )

        project
      end

      private

      def create_project!(attributes)
        owner = model_from_source_url!(attributes["owner"])
        creator = user_or_fallback(attributes["creator"])
        number = last_part_of_url(attributes["url"]).to_i

        import_model(
          Project.new(
            attributes.slice(
              "name", "body", "created_at", "closed_at", "deleted_at"
            ).merge(
              owner:   owner,
              creator: creator,
              number:  number,
              public:  import_as_public?(attributes),
            ),
          )
        )
      end

      # Internal: Determine public/private settings for project import.
      # If we're importing into Enterprise, read in the setting from archive.
      # If we're importing into GitHub.com, ALWAYS import as private
      def import_as_public?(attributes)
        return attributes.fetch("public", false) if GitHub.enterprise?
        false
      end

      def import_columns_and_cards!(project:, column_hashes:)
        column_hashes.each do |column_hash|
          column = fetch_or_add_column!(
            project:     project,
            column_hash: column_hash,
          )

          column_hash["cards"].each do |card_hash|
            next if repository_missing_for_card?(card_hash)

            fetch_or_add_card!(
              column:    column,
              card_hash: card_hash,
            )
          end
        end
      end

      def fetch_or_add_column!(project:, column_hash:)
        project.columns.find_by(
          column_hash.slice("name"),
        ) || project.columns.create!(
          column_hash.slice("name", "position", "hidden_at"),
        )
      rescue ActiveRecord::RecordNotUnique
        retry # rubocop:disable GitHub/UnboundedRetries https://github.com/github/github/issues/134043
      end

      def fetch_or_add_card!(column:, card_hash:)
        content = card_content(card_hash)
        creator = user_or_fallback(card_hash["creator"])
        priority = unique_priority_or_nil(column, card_hash)

        begin
          column.cards.find_by(
            creator_id:   creator.id,
            content_type: content&.class&.name,
            content_id:   content&.id,
            note:         card_hash["note"],
          ) || column.cards.create!(
            creator:   creator,
            content:   content,
            note:      card_hash["note"],
            priority:  priority,
            hidden_at: card_hash["hidden_at"],
            updated_at: card_hash["updated_at"],
            archived_at: card_hash["archived_at"],
          )
        rescue ActiveRecord::RecordNotUnique
          retry # rubocop:disable GitHub/UnboundedRetries https://github.com/github/github/issues/134043
        end
      end

      def card_content(card_hash)
        return unless card_hash["content"].present?

        model = model_from_source_url(card_hash["content"])
        model.is_a?(PullRequest) ? model.issue : model # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end

      def repository_missing_for_card?(card_hash)
        return false if card_hash["content"].blank?
        model_from_source_url(card_hash["content"]).nil?
      end

      def card_exists_by_priority?(column, card_hash)
        column.cards.exists?(priority: card_hash["priority"])
      end

      def unique_priority_or_nil(column, card_hash)
        card_hash["priority"] unless card_exists_by_priority?(column, card_hash)
      end
    end
  end
end
