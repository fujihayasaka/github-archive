# typed: strict
# frozen_string_literal: true

class MemexProject
  module MemexWithoutLimitsBetaDependency
    extend T::Sig
    extend T::Helpers

    requires_ancestor { MemexProject }

    sig { params(actor: User).returns(T::Boolean) }
    def add_to_beta_waitlist(actor)
      EarlyAccessMembership.new(
        actor:,
        member: self,
        feature_slug: "memex_table_without_limits",
        survey: MemexWithoutLimitsBetaWaitlistSurvey.find_or_create_survey
      ).save
    end

    sig { void }
    def remove_from_beta
      GitHub.flipper[:memex_table_without_limits].disable(self)
    end

    # Part of the Memex Without Limits (mwl) beta signup process.
    # https://github.com/github/projects-platform/issues/1490
    sig { returns(T::Boolean) }
    def eligible_for_memex_without_limits_waitlist?
      mwl_safe_rollout_flag_on? &&
        old_enough_for_mwl? &&
        enough_items_for_mwl? &&
        only_supported_fields_for_mwl?(false) &&
        no_insights_charts?
    end

    # Part of the Memex Without Limits (mwl) beta signup process for staffship users
    # https://github.com/github/projects-platform/issues/1677
    sig { returns(T::Boolean) }
    def eligible_for_staffship_memex_without_limits_waitlist?
      mwl_staffship_safe_rollout_flag_on? &&
        is_internal_project? &&
        only_supported_fields_for_mwl?(true) &&
        no_insights_charts?
    end


    sig { returns(T::Boolean) }
    private def mwl_safe_rollout_flag_on?
      T.let(GitHub.flipper[:memex_without_limits_banner_safe_rollout].enabled?, T::Boolean)
    end

    sig { returns(T::Boolean) }
    private def mwl_staffship_safe_rollout_flag_on?
      T.let(GitHub.flipper[:memex_without_limits_staffship_banner_safe_rollout].enabled?, T::Boolean)
    end

    sig { returns(T::Boolean) }
    private def old_enough_for_mwl?
      T.must(self.created_at) <= DateTime.current - MWL_MINIMUM_AGE_THRESHOLD
    end

    sig { returns(T::Boolean) }
    private def enough_items_for_mwl?
      self.memex_project_items.for_page_limit.count >= MWL_MINIMUM_ITEM_THRESHOLD
    end

    sig { params(support_slice_by: T::Boolean).returns(T::Boolean) }
    private def only_supported_fields_for_mwl?(support_slice_by)
      views = self.memex_project_views

      # slice by is not yet supported
      return false unless support_slice_by || views.pluck(:slice_by).compact.all?(&:empty?)
      # swimlanes are not yet supported
      return false if views.any? do |view|
        view.layout == "board_layout" && view.group_by.present?
      end

      column_types = ::MemexProjectColumn
        .where(id: views.pluck(:visible_fields).flatten.uniq)
        .pluck(:data_type)
        .uniq

      (column_types & MWL_UNSUPPORTED_FIELD_TYPES).empty?
    end

    sig { returns(T::Boolean) }
    private def no_insights_charts?
      self.charts.empty?
    end

    sig { returns(T::Boolean) }
    private def is_internal_project?
      self.owner.display_login == "github" || self.owner.display_login == "unicorns-r-us"
    end
  end
end
