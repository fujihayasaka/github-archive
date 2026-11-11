# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "csv"

# Repairs orgs that were partially processed by the starter pack transition.
# Reads org IDs from a CSV file committed to this branch.
#
# The replication lag bug caused two clean failure signatures (and only two):
#
#   Scenario A — options-stage failure:
#     fields > 0, options == 0, template == nil, mappings == 0, pinned == 0
#     (insert_all! on fields succeeded; re-query missed rows; everything after
#     options was never written.)
#
#   Scenario B — mappings-stage failure:
#     fields > 0, options > 0, template present, mappings == 0, pinned == 0
#     (insert_all! on template succeeded; re-query returned nil; mappings and
#     pinned were never written.)
#
# Orgs that don't match one of these signatures exactly are SKIPPED and logged
# as SKIP_UNEXPECTED_STATE. This protects orgs where a user has manually
# deleted some data after enabling the :issue_fields FF — we won't reinstate
# anything that wasn't lost to replication lag.
#
# Idempotent: re-running on a repaired org will classify it as "already complete".
# Uses write_to with re-queries inside the block to avoid replication lag.
module GitHub
  module Transitions
    class RepairIncompleteStarterPackOrgs < Base
      iterate_over :csv, params: {
        csv_file: "lib/github/transitions/data/incomplete_starter_pack_org_ids.csv",
        csv_read_opts: { headers: true, header_converters: :symbol },
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        org_ids = items.values.map { |v| v[:org_id].to_i }
        return if org_ids.empty?

        org_ids.each do |org_id|
          repair_org(org_id)
        end
      end

      private

      sig { params(org_id: Integer).void }
      def repair_org(org_id)
        fields = IssueField.where(owner_id: org_id).to_a
        if fields.empty?
          log("SKIP_NO_FIELDS org_id:#{org_id}")
          return
        end

        # Query options by issue_field_id, not owner_id — issue_field_options has
        # no index on owner_id (only on (issue_field_id, name)), so an owner_id
        # filter does a full table scan. Production timed out on this query.
        options_count  = IssueFieldOption.where(issue_field_id: fields.map(&:id)).count
        template       = PlanningTemplate.find_by(owner_id: org_id, template_type: PlanningTemplate::TEMPLATE_TYPES[:default])
        # Include owner_id so MySQL can use the composite indexes that lead with owner_id.
        # See https://github.com/github/github/pull/430618 for the same fix on the same tables.
        mappings_count = template ? PlanningTemplatesTypeFieldsMapping.where(owner_id: org_id, planning_template_id: template.id).count : 0
        pinned_count   = template ? PlanningTemplatesPinnedField.where(owner_id: org_id, planning_template_id: template.id).count : 0

        scenario =
          if options_count == 0 && template.nil? && mappings_count == 0 && pinned_count == 0
            :a
          elsif options_count > 0 && template && mappings_count == 0 && pinned_count == 0
            :b
          elsif template && mappings_count > 0 && pinned_count > 0
            :complete
          else
            :unexpected
          end

        state = "fields:#{fields.count} options:#{options_count} template:#{!template.nil?} mappings:#{mappings_count} pinned:#{pinned_count}"

        case scenario
        when :complete
          log("ALREADY_COMPLETE org_id:#{org_id} #{state}")
          return
        when :unexpected
          log("SKIP_UNEXPECTED_STATE org_id:#{org_id} #{state}")
          return
        end

        field_lookup = fields.index_by(&:name)
        repaired = []

        if scenario == :a
          repaired.concat(create_all_options(org_id, field_lookup))
          template = create_template(org_id)
          repaired << "template" if template
        end

        if template
          count = create_all_mappings(org_id, template, field_lookup)
          repaired << "mappings:#{count}" if count > 0

          repaired << "pinned" if create_pinned(org_id, template, field_lookup)
        end

        prefix = dry_run? ? "DRY_RUN_REPAIR" : "REPAIRED"
        log("#{prefix} org_id:#{org_id} scenario:#{scenario} #{repaired.join(', ')}")
      rescue => e
        log("ERROR repairing org_id:#{org_id}: #{e.class}: #{e.message} at #{e.backtrace&.first}")
        raise
      end

      sig { params(org_id: Integer, field_lookup: T::Hash[String, IssueField]).returns(T::Array[String]) }
      def create_all_options(org_id, field_lookup)
        return ["options"] if dry_run?

        now = Time.current
        option_inserts = IssueField::Defaults::FIELDS.select { |f| f[:options] }.flat_map do |field_data|
          field = field_lookup[field_data[:name]]
          next [] unless field

          T.cast(field_data[:options], T::Array[T::Hash[Symbol, T.untyped]]).map do |option_data|
            {
              owner_id: org_id,
              issue_field_id: field.id,
              name: option_data[:name],
              color: IssueFieldOption::COLORS[option_data[:color]],
              priority: option_data[:priority],
              created_at: now,
              updated_at: now,
            }
          end
        end

        write_to(model_class: IssueFieldOption) do
          IssueFieldOption.insert_all!(option_inserts)
        end

        ["options:#{option_inserts.size}"]
      end

      sig { params(org_id: Integer).returns(T.nilable(PlanningTemplate)) }
      def create_template(org_id)
        return nil if dry_run?

        org = User.find_by(id: org_id)
        unless org
          log("Skipping org_id:#{org_id} — org no longer exists")
          return nil
        end

        now = Time.current
        created_template = T.let(nil, T.nilable(PlanningTemplate))

        write_to(model_class: PlanningTemplate) do
          PlanningTemplate.insert_all!([{
            owner_id: org_id,
            name: "Default Planning Template",
            description: "Default planning template for #{org.display_login}",
            template_type: PlanningTemplate::TEMPLATE_TYPES[:default],
            created_at: now,
            updated_at: now,
          }])

          created_template = PlanningTemplate.find_by(owner_id: org_id, template_type: PlanningTemplate::TEMPLATE_TYPES[:default])
        end

        created_template
      end

      sig { params(org_id: Integer, template: PlanningTemplate, field_lookup: T::Hash[String, IssueField]).returns(Integer) }
      def create_all_mappings(org_id, template, field_lookup)
        issue_types = IssueType.where(owner_id: org_id)
        return 0 if issue_types.empty?

        now = Time.current
        mapping_inserts = issue_types.flat_map do |issue_type|
          field_names = IssueField::Defaults::FIELD_MAPPINGS.fetch(issue_type.name, IssueField::Defaults::DEFAULT_TYPE_FIELDS)
          field_names.each_with_index.filter_map do |field_name, position|
            field = field_lookup[field_name]
            next unless field

            {
              planning_template_id: template.id,
              owner_id: org_id,
              issue_type_id: issue_type.id,
              issue_field_id: field.id,
              position: position,
              created_at: now,
              updated_at: now,
            }
          end
        end

        return 0 if mapping_inserts.empty?

        unless dry_run?
          write_to(model_class: PlanningTemplatesTypeFieldsMapping) do
            PlanningTemplatesTypeFieldsMapping.insert_all!(mapping_inserts)
          end
        end

        mapping_inserts.size
      end

      sig { params(org_id: Integer, template: PlanningTemplate, field_lookup: T::Hash[String, IssueField]).returns(T::Boolean) }
      def create_pinned(org_id, template, field_lookup)
        priority = field_lookup["Priority"]
        return false unless priority

        unless dry_run?
          now = Time.current
          write_to(model_class: PlanningTemplatesPinnedField) do
            PlanningTemplatesPinnedField.insert_all!([{
              planning_template_id: template.id,
              owner_id: org_id,
              issue_field_id: priority.id,
              position: 0,
              created_at: now,
              updated_at: now,
            }])
          end
        end

        true
      end
    end
  end
end

if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)
  GitHub::Transitions::RepairIncompleteStarterPackOrgs.new(args).run
end
