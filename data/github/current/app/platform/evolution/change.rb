# typed: true
# frozen_string_literal: true

module Platform
  module Evolution
    # Information about an upcoming schema change.
    #
    # Since this object is possibly set on multiple
    # schema members for a single change, it's not possible
    # to know the exact name of the member. It only describes
    # a type of change but not the exact change on a member.
    #
    # See `Platform::Evolution::UpcomingChange`. It is built at boot time and holds
    # the member identifier. It represents a single upcoming change for the schema.
    class Change
      BREAKING = :breaking
      DANGEROUS = :dangerous

      attr_reader :target, :description, :reason, :apply_on, :criticality, :owner

      def initialize(target, description:, added_on:, reason:, criticality:, owner:, override_sunset_date: nil)
        @target = target
        @description = description
        @added_on = added_on
        @override_sunset_date = override_sunset_date
        @apply_on = self.class.change_date(added_on)
        @apply_on = override_sunset_date if override_sunset_date
        @reason = reason
        @criticality = criticality
        @owner = owner
      end

      def self.build_removal_change(target, added_on:, reason:, owner:, superseded_by: nil, override_sunset_date: nil)
        description = "`#{target.graphql_name}` will be removed."

        if superseded_by
          description = description + " #{superseded_by}"
        end

        new(
          target,
          description: description,
          added_on: added_on,
          reason: reason,
          criticality: BREAKING,
          owner: owner,
          override_sunset_date: override_sunset_date,
        )
      end

      def self.build_type_change(target, new_type:, added_on:, reason:, owner:)
        new(
          target,
          description: "Type for `#{target.graphql_name}` will change from `#{target.type.to_type_signature}` to `#{new_type}`.",
          added_on: added_on,
          reason: reason,
          criticality: BREAKING,
          owner: owner,
        )
      end

      def self.change_date(added_on)
        # Give a *minimum* of three months. Deprecate
        # the quarter after the next one.
        quarter = (added_on.month / 3.0).ceil
        change_quarter = quarter + 2

        year_offset = 0
        if change_quarter > 4
          change_quarter = change_quarter % 4
          year_offset = 1
        end

        # Get beginning of quarter
        change_quarter_first_month = (change_quarter * 3) - 2
        DateTime.new(added_on.year + year_offset, change_quarter_first_month, 1)
      end

      def idl_description
        "**Upcoming Change on #{apply_on.strftime("%F UTC")}**\n" \
        "**Description:** #{description}\n" \
        "**Reason:** #{reason}\n"
      end

      def active?
        # A schema member change is only active when the feature is enabled
        # And never active in enterprise. We don't need runtime modifications
        # for enterprise and only sunset through enterprise *versions* instead.
        GitHub.flipper[switch_flag].enabled? && !GitHub.enterprise?
      end

      def switch_flag
        :"deprecation-sunset-#{apply_on.strftime("%F")}"
      end
    end
  end
end
