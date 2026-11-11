# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Diagnostic transition: finds orgs that have issue fields but are missing
# options, planning templates, mappings, or pinned fields.
#
# These orgs were partially processed by the starter pack transition due to
# replication lag causing re-queries to miss newly inserted records.
#
# Iterates the issue_fields table (not users) so we only process orgs that
# actually have fields — avoids scanning hundreds of millions of user records.
#
# Run as dry-run only — this transition does not write any data.
# Extract org IDs from the logs to build a CSV for the repair transition.
module GitHub
  module Transitions
    class FindIncompleteStarterPackOrgs < Base
      include GitHub::Memoizer

      iterate_over :database_table, params: {
        model_class: IssueField,
        columns: [:owner_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        # Items are keyed by IssueField ID — extract unique org IDs
        org_ids = items.values.map { |v| v[:owner_id] }.uniq
        return if org_ids.empty?

        # Skip orgs where the issue_fields FF is enabled — those orgs can
        # self-manage their fields, so missing data may be intentional.
        ff_enabled_org_ids = issue_fields_enabled_org_ids
        org_ids = org_ids.reject { |id| ff_enabled_org_ids.include?(id) }
        return if org_ids.empty?

        expected_field_names = IssueField::Defaults::FIELDS.map { |f| f[:name] }.sort
        expected_field_count = expected_field_names.size
        expected_option_count = 7 # Priority: 4, Effort: 3

        # Batch all lookups upfront to avoid N+1
        fields_by_org = IssueField.where(owner_id: org_ids).group_by(&:owner_id)
        # issue_field_options has no index on owner_id (only on (issue_field_id, name)),
        # so a WHERE owner_id IN (...) does a full table scan. Query by issue_field_id
        # using the IDs we already loaded above.
        field_ids_by_org = fields_by_org.transform_values { |fs| fs.map(&:id) }
        all_field_ids = field_ids_by_org.values.flatten
        options_count_by_field = if all_field_ids.any?
          IssueFieldOption.where(issue_field_id: all_field_ids).group(:issue_field_id).count
        else
          {}
        end
        options_count_by_org = field_ids_by_org.transform_values do |fids|
          fids.sum { |fid| options_count_by_field[fid] || 0 }
        end
        templates_by_org = PlanningTemplate
          .where(owner_id: org_ids, template_type: PlanningTemplate::TEMPLATE_TYPES[:default])
          .index_by(&:owner_id)

        template_ids = templates_by_org.values.map(&:id)
        # Include owner_id so MySQL can use the composite indexes that lead with owner_id.
        # See https://github.com/github/github/pull/430618 for the same fix on the same tables.
        pinned_counts_by_template = PlanningTemplatesPinnedField.where(owner_id: org_ids, planning_template_id: template_ids).group(:planning_template_id).count
        mapping_counts_by_template = PlanningTemplatesTypeFieldsMapping.where(owner_id: org_ids, planning_template_id: template_ids).group(:planning_template_id).count
        type_counts_by_org = IssueType.where(owner_id: org_ids).group(:owner_id).count

        org_ids.each do |org_id|
          issues = []

          # Check fields
          org_fields = fields_by_org[org_id] || []
          field_names = org_fields.map(&:name).sort
          if field_names != expected_field_names
            issues << "fields:#{org_fields.size}/#{expected_field_count}"
          end

          # Check options
          option_count = options_count_by_org[org_id] || 0
          if option_count != expected_option_count
            issues << "options:#{option_count}/#{expected_option_count}"
          end

          # Check planning template
          template = templates_by_org[org_id]
          unless template
            issues << "no_template"
          end

          # Check pinned field + mappings
          if template
            pinned_count = pinned_counts_by_template[template.id] || 0
            if pinned_count != 1
              issues << "pinned:#{pinned_count}/1"
            end

            type_count = type_counts_by_org[org_id] || 0
            if type_count > 0
              mapping_count = mapping_counts_by_template[template.id] || 0
              if mapping_count == 0
                issues << "no_mappings(#{type_count}_types)"
              end
            end
          else
            issues << "no_pinned"
            issues << "no_mappings"
          end

          if issues.any?
            log("INCOMPLETE org_id:#{org_id} issues:#{issues.join(',')}")
          end
        end
      end

      private

      # Returns the set of org IDs that have the :issue_fields FF enabled.
      # Cached for the lifetime of the transition to avoid repeated lookups.
      sig { returns(T::Set[Integer]) }
      memoize def issue_fields_enabled_org_ids
        if FeatureFlag.vexi.enabled?(:issue_fields, default: false)
          log("WARNING: :issue_fields FF is globally enabled — all orgs have the FF, skipping none")
          Set.new
        else
          actor_ids = GitHub::VexiActor.actor_ids_by_class_or_raise(:issue_fields)
          (actor_ids.to_h[Organization] || []).map(&:to_i).to_set
        end
      end
    end
  end
end

if $0 == __FILE__
  args = GitHub::Transitions::Arguments.parse(ARGV)
  GitHub::Transitions::FindIncompleteStarterPackOrgs.new(args).run
end
