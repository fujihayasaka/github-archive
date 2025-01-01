# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module SecretScanning
      class ByValidity
        extend T::Sig
        include Filter

        VALIDITY_FILTERS = T.let([:unknown, :inactive, :active], T::Array[Symbol])
        TokenValidity = SecretScanningAlertRevision::SecretScanningTokenValidity

        sig { returns(T::Array[Symbol]) }
        attr_reader :incl_filters, :excl_filters

        sig { params(incl_filters: T::Array[String], excl_filters: T::Array[String]).void }
        def initialize(incl_filters, excl_filters)
          @incl_filters = T.let(incl_filters.uniq.map(&:to_sym), T::Array[Symbol])
          @excl_filters = T.let(excl_filters.uniq.map(&:to_sym), T::Array[Symbol])
        end

        sig { override.params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          if incl_filters.present?
            # Get net filters so we only need to build one query
            net_filters = incl_filters - excl_filters

            valid_filters = to_token_validities(net_filters)
            return rel.none if valid_filters.empty?

            return revisions_with_current_validities(rel, valid_filters)
          end

          if excl_filters.present?
            valid_filters = to_token_validities(excl_filters)
            return rel if valid_filters.empty?

            return revisions_with_current_validities(rel, valid_filters, negated: true)
          end

          rel
        end

        sig { override.returns(T::Boolean) }
        def is_empty?
          @incl_filters.blank? && @excl_filters.blank?
        end

        sig { override.returns(T::Boolean) }
        def has_incl_filters?
          @incl_filters.present?
        end

        sig { returns(T::Array[Symbol]) }
        def selected_filters
          # Consider all validity statuses if nothing is selected
          return VALIDITY_FILTERS if is_empty?
          net_filters = if @incl_filters.present?
            @incl_filters - @excl_filters
          else
            VALIDITY_FILTERS - @excl_filters
          end
          net_filters.select { |f| VALIDITY_FILTERS.include?(f) }
        end

        sig { params(filters: T::Array[Symbol]).returns(T::Array[Integer]) }
        def to_token_validities(filters)
          filters = filters.select { |f| VALIDITY_FILTERS.include?(f) }
          return [] if filters.empty?
          SecretScanningAlertRevision.to_token_validities(filters)
        end

        private

        sig { params(rel: ActiveRecord::Relation, validities: T::Array[Integer], negated: T::Boolean).returns(ActiveRecord::Relation) }
        def revisions_with_current_validities(rel, validities, negated: false)
          if negated
            rel.joins(
              "INNER JOIN #{SecretScanningAlertRevision.table_name} AS `latest_revs`" \
                " ON `latest_revs`.`repository_id` = `#{SecretScanningAlertRevision.table_name}`.`repository_id`" \
                " AND `latest_revs`.`alert_number` = `#{SecretScanningAlertRevision.table_name}`.`alert_number`" \
                " AND `latest_revs`.`next_revision_date_id` = #{SecurityOverviewAnalytics::Date::FUTURE_DATE_ID}" \
                " AND `latest_revs`.`alert_validity` NOT IN (#{validities.join(",")})"
            )
          else
            rel.joins(
              "INNER JOIN #{SecretScanningAlertRevision.table_name} AS `latest_revs`" \
                " ON `latest_revs`.`repository_id` = `#{SecretScanningAlertRevision.table_name}`.`repository_id`" \
                " AND `latest_revs`.`alert_number` = `#{SecretScanningAlertRevision.table_name}`.`alert_number`" \
                " AND `latest_revs`.`next_revision_date_id` = #{SecurityOverviewAnalytics::Date::FUTURE_DATE_ID}" \
                " AND `latest_revs`.`alert_validity` IN (#{validities.join(",")})"
            )
          end
        end
      end
    end
  end
end
