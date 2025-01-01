# frozen_string_literal: true

module AdvisoryReviews
  class SidebarComponent < ApplicationComponent
    attr_reader :advisory_review

    delegate :advisory, :cve_id, :cve_url, :ghsa_id, :npm_id, :blocklisted_terms, :labels, to: :advisory_review

    def initialize(advisory_review:)
      @advisory_review = advisory_review
    end

    def new_approval
      advisory_review.approvals.build
    end

    def show_approvals?
      approvals.present? || advisory_review.curation_state == "open_update"
    end

    def approvals
      approvals = []
      case advisory_review.curation_state
      when "open_create", "ready_to_publish", "ready_to_withdraw"
        approvals = advisory_review.approvals.current_review_request.to_a
        (AdvisoryReviewApproval::REQUIRED_APPROVAL_COUNT - approvals.size).times do
          approvals << new_approval
        end
      when "open_update"
        approvals = advisory_review.approvals.current_review_request.unapproved.to_a
      end

      approvals
    end

    def curators
      AdvisoryDB::Config::ActiveCurators::CURATORS
    end

    def show_update_button?
      !advisory_review.read_only?
    end

    def show_advisory_review_buttons?
      show_update_button? ||
        show_close_button? ||
        show_revert_button? ||
        show_reopen_button?
    end

    def show_advisory_buttons?
      show_publish_button? ||
        show_withdraw_button? ||
        show_approve_for_publication_button? ||
        show_approve_for_withdrawal_button?
    end

    def show_close_button?
      advisory_review.may_reject? && advisory_review.advisory.nil?
    end

    def show_revert_button?
      advisory_review.may_revert?
    end

    def show_reopen_button?
      advisory_review.may_restart_review? || advisory_review.may_revisit?
    end

    def show_approve_for_publication_button?
      advisory_review.may_approve_to_publish? && !advisory_review.required_approvals?
    end

    def show_publish_button?
      return true if advisory_review.approved_to_publish?

      (advisory_review.open? || advisory_review.in_review?) && advisory_review.required_approvals?
    end

    def show_approve_for_withdrawal_button?
      advisory_review.may_approve_to_withdraw? && advisory && !advisory.withdrawn?
    end

    def show_withdraw_button?
      advisory_review.approved_to_withdraw?
    end

    def show_grouped_buttons?
      AdvisoryDB::Features.enabled?("advisory_db_advisory_review_grouped_buttons")
    end

    def show_grouped_publish_buttons?
      show_approve_for_publication_button? || show_publish_button?
    end

    def show_grouped_withdraw_buttons?
      show_approve_for_withdrawal_button? || show_withdraw_button?
    end

    def grouped_approve_for_publication_button_disabled?
      publish_disabled? || !show_approve_for_publication_button?
    end

    def grouped_publish_button_disabled?
      publish_disabled? || !show_publish_button?
    end

    def grouped_approve_for_withdrawal_button_disabled?
      !checks_passed? || !show_approve_for_withdrawal_button?
    end

    def grouped_withdraw_button_disabled?
      !checks_passed? || !show_withdraw_button?
    end

    def grouped_publish_button_label
      if publish_updates_withdrawn_advisory?
        "Update withdrawn advisory"
      elsif publish_updates_published_advisory?
        "Update published advisory"
      else
        "Publish advisory"
      end
    end
    alias publish_button_label grouped_publish_button_label

    def grouped_publish_stages
      return @grouped_publish_stages if defined? @grouped_publish_stages

      @grouped_publish_stages = {
        stage_one: TwoStageApprovals::Stage.new(
          label: "Ready to publish",
          disabled: grouped_approve_for_publication_button_disabled?,
          icon: :thumbsup,
          action: "review",
          past_tense_action: "reviewed",
          confirmation_url: approve_advisory_review_path(advisory_review),
          confirmation_params: { approval_type: "publish" },
          test_selector: "advisory-review-sidebar-ready-to-publish-button",
        ),
        stage_two: TwoStageApprovals::Stage.new(
          label: publish_button_label,
          disabled: grouped_publish_button_disabled?,
          icon: :rocket,
          action: "publish",
          past_tense_action: "published",
          confirmation_url: publish_advisory_review_path(advisory_review),
          test_selector: "advisory-review-sidebar-publish-button",
        ),
      }
    end

    def grouped_withdraw_stages
      return @grouped_withdraw_stages if defined? @grouped_withdraw_stages

      @grouped_withdraw_stages = {
        stage_one: TwoStageApprovals::Stage.new(
          label: "Ready to withdraw",
          disabled: grouped_approve_for_withdrawal_button_disabled?,
          icon: :thumbsup,
          action: "review",
          past_tense_action: "reviewed",
          confirmation_url: approve_advisory_review_path(advisory_review),
          confirmation_params: { approval_type: "withdraw" },
          scheme: :danger,
          test_selector: "advisory-review-sidebar-ready-to-withdraw-button",
        ),
        stage_two: TwoStageApprovals::Stage.new(
          label: "Withdraw advisory",
          disabled: grouped_withdraw_button_disabled?,
          icon: :"no-entry",
          action: "withdraw",
          past_tense_action: "withdrawn",
          confirmation_url: withdraw_advisory_review_path(advisory_review),
          scheme: :danger,
          test_selector: "advisory-review-sidebar-withdraw-button",
        ),
      }
    end

    def show_campaign?
      advisory_review.campaigns.present?
    end

    def associated_campaigns
      @associated_campaigns ||= advisory_review.campaigns
    end

    def publish_updates_withdrawn_advisory?
      advisory.present? && advisory.withdrawn?
    end

    def publish_updates_published_advisory?
      advisory.present? && !advisory.withdrawn?
    end

    def publish_disabled?
      !checks_passed? || (advisory && !show_publish_diff?)
    end

    def publish_disabled_reason
      if publish_disabled? && advisory_review.held_from_publishing?
        "This review cannot be published due to a label assigned with 'hold'."
      end
    end

    def show_publish_diff?
      publish_diff.diff.present?
    end

    def publish_diff
      return @publish_diff if defined? @publish_diff

      @publish_diff = Publisher.new(advisory_review).diff
    end

    def show_checks?
      checks.any?
    end

    def checks_passed?
      return @checks_passed if defined? @checks_passed

      @checks_passed = CheckSuiteRunner.checks_passed?(review: advisory_review)
    end

    def checks
      @checks ||= CheckSuiteRunner.get_checks(review: advisory_review)
    end

    def show_blocklist?
      blocklisted_terms.any?
    end
  end
end
