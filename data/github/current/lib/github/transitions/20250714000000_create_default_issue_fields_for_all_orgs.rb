# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Creates default issue fields (Priority, Start date, Target date, Effort) for all organizations.
# Uses insert_all! for bulk operations — bypasses AR callbacks to avoid ~70M Hydro events.
#
# Idempotent: skips orgs that already have any issue fields.
# Resumable: use --start_id / --end_id to resume from failures.
#
# Prior art: CreateDefaultIssueTypesForOrgsTransition (7M orgs, same pattern)
#
# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class CreateDefaultIssueFieldsForAllOrgs < Base
      iterate_over :database_table, params: {
        model_class: User,
        conditions: "type = 'Organization'"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        orgs = User.where(id: items.keys).to_a
        return if orgs.empty?

        orgs_with_fields = IssueField.where(owner_id: orgs.map(&:id)).distinct.pluck(:owner_id).to_set
        pending_org_ids = orgs.filter_map { |org| org.id unless orgs_with_fields.include?(org.id) }
        skipped = orgs.size - pending_org_ids.size

        if dry_run?
          if pending_org_ids.size <= 20
            pending_org_ids.each do |org_id|
              org = orgs.find { |o| o.id == org_id }
              log("Dry run: would create fields for #{org&.display_login} (id: #{org_id})")
            end
          end
          log("Dry run batch (ids #{orgs.map(&:id).min}..#{orgs.map(&:id).max}): #{pending_org_ids.size} to process, #{skipped} skipped (already have fields)")
          return
        end

        log("Processing batch of #{orgs.size} orgs (ids #{orgs.map(&:id).min}..#{orgs.map(&:id).max})")

        return if pending_org_ids.empty?

        created_fields_by_org = create_fields_for_batch(pending_org_ids)
        create_mappings_for_batch(created_fields_by_org)
        log("Created fields for #{created_fields_by_org.size}/#{orgs.size} orgs (#{skipped} skipped), org_ids: #{pending_org_ids.inspect}")
      rescue => e
        log("ERROR in batch (org_ids: #{pending_org_ids.inspect}): #{e.class}: #{e.message} at #{e.backtrace&.first}")
        raise
      end

      private

      # Bulk-create the 4 starter pack fields + options for a batch of org IDs.
      # Returns { org_id => { field_name => field_id } } for mapping creation.
      sig { params(org_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Hash[String, Integer]]) }
      def create_fields_for_batch(org_ids)
        now = Time.current
        ghost_id = User.ghost.id

        field_inserts = org_ids.flat_map do |org_id|
          IssueField::Defaults::FIELDS.map do |field_data|
            {
              owner_id: org_id,
              name: field_data[:name],
              name_slug: field_data[:name].parameterize,
              description: field_data[:description],
              data_type: IssueField::DATA_TYPES[field_data[:data_type].to_sym],
              priority: field_data[:priority],
              actor_id: ghost_id,
              visibility: IssueField::VISIBILITIES[:org_only],
              created_at: now,
              updated_at: now,
            }
          end
        end

        # insert_all! doesn't return generated IDs on MySQL, so we re-query
        # inside write_to to read from the primary and avoid replication lag
        created_fields_by_org = T.let({}, T::Hash[Integer, T::Hash[String, Integer]])

        write_to(model_class: IssueField) do
          IssueField.insert_all!(field_inserts)

          IssueField
            .where(owner_id: org_ids)
            .pluck(:id, :owner_id, :name)
            .each do |field_id, owner_id, name|
              created_fields_by_org[owner_id] ||= {}
              T.must(created_fields_by_org[owner_id])[name] = field_id
            end
        end

        option_inserts = org_ids.flat_map do |org_id|
          org_fields = T.must(created_fields_by_org[org_id])

          IssueField::Defaults::FIELDS.select { |f| f[:options] }.flat_map do |field_data|
            field_id = T.must(org_fields[field_data[:name]])

            T.cast(field_data[:options], T::Array[T::Hash[Symbol, T.untyped]]).map do |option_data|
              {
                owner_id: org_id,
                issue_field_id: field_id,
                name: option_data[:name],
                color: IssueFieldOption::COLORS[option_data[:color]],
                priority: option_data[:priority],
                created_at: now,
                updated_at: now,
              }
            end
          end
        end

        write_to(model_class: IssueFieldOption) do
          IssueFieldOption.insert_all!(option_inserts)
        end

        created_fields_by_org
      end

      # Bulk-create field-to-issue-type mappings and pinned fields for a batch of orgs.
      sig { params(created_fields_by_org: T::Hash[Integer, T::Hash[String, Integer]]).void }
      def create_mappings_for_batch(created_fields_by_org)
        org_ids = created_fields_by_org.keys
        now = Time.current

        issue_types_by_org = IssueType.where(owner_id: org_ids).group_by(&:owner_id)

        existing_templates = PlanningTemplate
          .where(owner_id: org_ids, template_type: PlanningTemplate::TEMPLATE_TYPES[:default])
          .index_by(&:owner_id)

        missing_template_org_ids = org_ids - existing_templates.keys
        if missing_template_org_ids.any?
          orgs_by_id = User.where(id: missing_template_org_ids).index_by(&:id)

          template_inserts = missing_template_org_ids.map do |org_id|
            {
              owner_id: org_id,
              name: "Default Planning Template",
              description: "Default planning template for #{orgs_by_id[org_id]&.display_login}",
              template_type: PlanningTemplate::TEMPLATE_TYPES[:default],
              created_at: now,
              updated_at: now,
            }
          end

          # Re-query inside write_to to read from primary, avoiding replication lag
          write_to(model_class: PlanningTemplate) do
            PlanningTemplate.insert_all!(template_inserts)

            new_templates = PlanningTemplate
              .where(owner_id: missing_template_org_ids, template_type: PlanningTemplate::TEMPLATE_TYPES[:default])
              .index_by(&:owner_id)
            existing_templates.merge!(new_templates)
          end
        end

        mapping_inserts = []
        pinned_field_inserts = []

        org_ids.each do |org_id|
          org_fields = T.must(created_fields_by_org[org_id])
          template = existing_templates[org_id]
          issue_types = issue_types_by_org[org_id] || []
          priority_field_id = T.must(org_fields["Priority"])

          issue_types.each do |issue_type|
            field_names = IssueField::Defaults::FIELD_MAPPINGS.fetch(issue_type.name, IssueField::Defaults::DEFAULT_TYPE_FIELDS)

            field_names.each_with_index do |field_name, position|
              mapping_inserts << {
                planning_template_id: template.id,
                owner_id: org_id,
                issue_type_id: issue_type.id,
                issue_field_id: T.must(org_fields[field_name]),
                position: position,
                created_at: now,
                updated_at: now,
              }
            end
          end

          pinned_field_inserts << {
            planning_template_id: template.id,
            owner_id: org_id,
            issue_field_id: priority_field_id,
            position: 0,
            created_at: now,
            updated_at: now,
          }
        end

        if mapping_inserts.any?
          write_to(model_class: PlanningTemplatesTypeFieldsMapping) do
            PlanningTemplatesTypeFieldsMapping.insert_all!(mapping_inserts)
          end
        end

        write_to(model_class: PlanningTemplatesPinnedField) do
          PlanningTemplatesPinnedField.insert_all!(pinned_field_inserts)
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::CreateDefaultIssueFieldsForAllOrgs.new(args).run
end
