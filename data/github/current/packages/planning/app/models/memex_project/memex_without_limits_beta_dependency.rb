# typed: strict
# frozen_string_literal: true

class MemexProject
  module MemexWithoutLimitsBetaDependency
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

    # Part of the Memex Without Limits (mwl) beta signup process.
    # https://github.com/github/projects-platform/issues/1490
    sig { returns(T::Boolean) }
    def eligible_for_memex_without_limits_waitlist?
      mwl_safe_rollout_flag_on? &&
        enough_items_for_mwl? &&
        only_supported_fields_for_mwl? &&
        no_insights_charts?
    end

    # Part of the Memex Without Limits (mwl) beta signup process for staffship users
    # https://github.com/github/projects-platform/issues/1677
    sig { returns(T::Boolean) }
    def eligible_for_staffship_memex_without_limits_waitlist?
      mwl_staffship_safe_rollout_flag_on? &&
        is_internal_project? &&
        only_supported_fields_for_mwl? &&
        no_insights_charts?
    end

    sig { returns(T::Boolean) }
    private def mwl_safe_rollout_flag_on?
      T.let(GitHub.flipper[:memex_without_limits_limited_public_beta_banner_safe_rollout].enabled?, T::Boolean)
    end

    sig { returns(T::Boolean) }
    private def mwl_staffship_safe_rollout_flag_on?
      T.let(GitHub.flipper[:memex_without_limits_staffship_banner_safe_rollout].enabled?, T::Boolean)
    end

    sig { returns(T::Boolean) }
    private def enough_items_for_mwl?
      self.memex_project_items.for_page_limit.count >= MWL_MINIMUM_ITEM_THRESHOLD
    end

    sig { returns(T::Boolean) }
    private def only_supported_fields_for_mwl?
      views = self.memex_project_views
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
