# typed: strict
# frozen_string_literal: true

module TradeControlsHelper
  extend T::Helpers

  abstract!

  # TODO: This should be T.nilable(User) but sorbet complains about 20+ files that then need to be fixed
  # Since the parent class returns T.untyped, this matches the signature there for now
  sig { abstract.returns(T.untyped) }
  def current_user; end

  sig { returns(String) }
  def trade_controls_unknown_error_notice
    TradeControls::Notices.unknown_error_generic
  end

  sig { returns(String) }
  def trade_controls_user_account_restricted_notice
    TradeControls::Notices.user_account_restricted_generic
  end

  sig { returns(String) }
  def trade_controls_secret_gist_restricted
    TradeControls::Notices.secret_gist_restricted
  end

  sig { returns(String) }
  def trade_controls_repo_disabled_notice
    TradeControls::Notices.repo_disabled_generic
  end

  sig { returns(String) }
  def trade_controls_private_repo_creation_warning
    TradeControls::Notices.free_private_repo_warning
  end

  sig { returns(String) }
  def trade_controls_user_private_repo_creation_warning
    TradeControls::Notices.free_private_repo_warning
  end

  sig { returns(String) }
  def trade_controls_organization_account_restricted_mail
    TradeControls::Notices.organization_account_enforcement_mail
  end

  sig { returns(String) }
  def trade_controls_restricted_free_org_allowed_mail
    TradeControls::Notices.restricted_free_org_allowed_mail
  end

  sig { returns(String) }
  def trade_controls_organization_billing_account_restricted
    TradeControls::Notices.billing_account_restricted
  end

  sig { params(generic: T::Boolean).returns(String) }
  def trade_controls_organization_repo_disabled_notice(generic: true)
    return TradeControls::Notices.organization_owned_repo_disabled_generic if generic
    TradeControls::Notices.notice_as_plaintext(:organization_owned_repo_disabled)
  end

  sig { returns(String) }
  def trade_controls_organization_repo_disabled_non_admins_notice
    TradeControls::Notices.organization_owned_repo_disabled_for_non_admins_generic
  end

  sig { returns(String) }
  def trade_controls_organization_sdn_restricted_notice
    TradeControls::Notices.organization_sdn_restricted
  end

  sig { returns(String) }
  def trade_controls_organization_invite_restricted_notice
    TradeControls::Notices.org_invite_restricted.html_safe #rubocop:disable Rails/OutputSafety
  end

  sig { returns(String) }
  def trade_controls_restricted_public_abilities_for_gist
    TradeControls::Notices.restricted_public_abilities_for(type: "gist")
  end

  sig { returns(String) }
  def trade_controls_coupon_application_not_screened_notice
    TradeControls::Notices.coupon_application_not_screened_notice
  end

  sig { returns(String) }
  def trade_controls_archived_admin_notice
    TradeControls::Notices.organization_owned_repo_archived_generic
  end

  sig { returns(String) }
  def trade_controls_archived_non_admins_notice
    TradeControls::Notices.organization_owned_repo_archived_for_non_admins_generic
  end

  sig { returns(String) }
  def trade_controls_archived_cta_for_admins
    TradeControls::Notices.archived_cta_for_admins.html_safe #rubocop:disable Rails/OutputSafety
  end

  sig { returns(String) }
  def trade_controls_archived_cta_for_non_admins
    TradeControls::Notices.archived_cta_for_non_admins.html_safe #rubocop:disable Rails/OutputSafety
  end

  sig { returns(String) }
  def trade_controls_archived_cta_for_sdn_restricted_admins
    TradeControls::Notices.archived_cta_for_sdn_restricted_admins.html_safe #rubocop:disable Rails/OutputSafety
  end

  sig { returns(String) }
  def trade_controls_free_org_restricted_notice
    TradeControls::Notices.free_organization_account_restricted
  end

  sig { params(organization: T.nilable(Organization)).returns(T::Boolean) }
  def should_show_free_org_restricted_banner?(organization)
    return false if current_user.dismissed_notice?(Billing::OFACCompliance::FREE_ORG_NOTICE_FLAG)
    return false unless organization&.organization?
    return false unless organization.uncharged_account?

    # we are currently transitioning how we handle restrictions to a tiered restriction model.
    # We will be removing partial trade restrictions in the future.
    organization.has_partial_trade_restrictions? || organization.has_any_tiered_trade_restrictions?
  end

  # START SDN TRADE SCREENING
  sig { returns(String) }
  def trade_screening_true_match_notice
    TradeControls::Notices.trade_screening_customer_account_disabled
  end

  sig { returns(String) }
  def trade_screening_generic_notice
    TradeControls::Notices.trade_screening_account_restricted_generic
  end

  sig { returns(String) }
  def trade_screening_spammy_notice
    TradeControls::Notices.trade_screening_account_spammy
  end

  sig { params(target: T.any(User, Organization, Business)).returns(String) }
  def trade_screening_pending_review_notice(target)
    if target.trade_screening_record.last_trade_screen_date_less_than_2_days_ago?
      trade_screening_pending_review_less_than_2_days_notice
    elsif target.trade_screening_record.last_trade_screen_date_less_than_7_days_ago?
      trade_screening_pending_review_between_2_to_7_days_notice
    else
      trade_screening_ineligible_for_transactions_notice
    end
  end

  sig { returns(String) }
  def trade_screening_ingestion_error_notice
    TradeControls::Notices.trade_screening_customer_account_ingestion_error
  end

  sig { returns(String) }
  def trade_screening_data_issue_name_error_notice
    TradeControls::Notices.trade_screening_customer_account_data_issue_name_error
  end

  sig { returns(String) }
  def trade_screening_data_issue_org_error_notice
    TradeControls::Notices.trade_screening_customer_account_data_issue_org_error
  end

  sig { returns(String) }
  def trade_screening_data_issue_address_error_notice
    TradeControls::Notices.trade_screening_customer_account_data_issue_address_error
  end

  sig { returns(String) }
  def trade_screening_data_issue_legal_id_error_notice
    TradeControls::Notices.trade_screening_customer_account_data_issue_legal_id_error
  end

  sig { returns(String) }
  def trade_screening_data_issue_other_error_notice
    TradeControls::Notices.trade_screening_customer_account_data_issue_other_error
  end

  sig { returns(String) }
  def trade_screening_pending_review_less_than_2_days_notice
    TradeControls::Notices.trade_screening_customer_account_under_review_for_less_than_2_days
  end

  sig { returns(String) }
  def trade_screening_pending_review_between_2_to_7_days_notice
    TradeControls::Notices.trade_screening_customer_account_under_review_between_2_to_7_days
  end

  sig { returns(String) }
  def trade_screening_ineligible_for_transactions_notice
    TradeControls::Notices.trade_screening_customer_account_permanently_blocked_after_review
  end

  sig { params(target: T.any(User, Organization, Business)).returns(String) }
  def trade_screening_data_issue_notice(target)
    # The keys in this hash will probably change!
    notice_hash = {
      "Data Issue - Name" => trade_screening_data_issue_name_error_notice,
      "Data Issue - Org" => trade_screening_data_issue_org_error_notice,
      "Data Issue - Address" => trade_screening_data_issue_address_error_notice,
      "Data Issue - Legal ID" => trade_screening_data_issue_legal_id_error_notice,
      "Data Issue - Other" => trade_screening_data_issue_other_error_notice,
    }

    notice_hash[target.trade_screening_record.screening_status_reason] || trade_screening_data_issue_other_error_notice
  end

  sig { params(target: T.nilable(T.any(User, Organization, Business)), check_for_current_user: T::Boolean, feature_type: Symbol).returns(String) }
  def trade_screening_restriction_notice(target: current_user, check_for_current_user: false, feature_type: :default)
    target_to_use = target
    restricted_target_exists = target&.has_commercial_interaction_restriction?(feature_type: feature_type)

    if check_for_current_user
      if target&.has_commercial_interaction_restriction?(feature_type: feature_type)
        target_to_use = target
        restricted_target_exists = true
      elsif current_user.has_commercial_interaction_restriction?(feature_type: feature_type)
        target_to_use = current_user
        restricted_target_exists = true
      end
    end

    return "" unless restricted_target_exists
    message = if target_to_use.trade_screening_record.ingestion_error?
      trade_screening_ingestion_error_notice
    elsif target_to_use.trade_screening_record.data_issue?
      trade_screening_data_issue_notice(target_to_use)
    elsif target_to_use.trade_screening_record.hit_in_review?
      trade_screening_pending_review_notice(target_to_use)
    elsif target_to_use.trade_screening_record.spammy?
      trade_screening_spammy_notice
    else
      trade_screening_ineligible_for_transactions_notice
    end
  end

  sig do
    params(
      target: Billing::Types::Account,
      title: String,
      description: T.nilable(String),
      class_name: T.nilable(String),
      check_for_current_user: T::Boolean,
      feature_type: Symbol,
      hide_title: T::Boolean
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def trade_screening_banner_react_payload(
    target: current_user,
    title: "",
    description: nil,
    class_name: nil,
    check_for_current_user: false,
    feature_type: :default,
    hide_title: false
  )
    restriction_notice = trade_screening_restriction_notice(
      target:,
      check_for_current_user:,
      feature_type:,
    )

    {
      isTradeRestricted: restriction_notice.present?,
      hideTitle: hide_title,
      title:,
      className: class_name,
      description: description || restriction_notice,
    }
  end
  # END SDN TRADE SCREENING
end
