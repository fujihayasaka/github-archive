# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Responsible for creating the following weekly digest issues for the
# GitHub Field Operations team to review:
#
# 1. Orgs that have recently been invited to an enterprise and the invitation has been confirmed.
# 2. New enterprises that have been created due to an upgrade of a standalone org.
class BusinessOrganizationInvitationReviewDigestJob < ApplicationJob
  schedule interval: 1.week, condition: -> { !GitHub.single_business_environment? }

  queue_as :business_organization_invitation_review_digest
  retry_on_dirty_exit

  # github/Field-Operations
  REPO_ID = 364382368

  # "Enterprise Account: Org Review"
  INVITATION_REVIEW_LABEL_ID = 7427380966

  # "Enterprise Account: Upgrade Review"
  UPGRADE_REVIEW_LABEL_ID = 7427382419

  def perform
    with_write do
      create_issue \
        "Organization invitations pending review - #{Date.today}",
        invitations_issue_body,
        invitations_digest_label
      create_issue \
        "Enterprise upgrades pending review - #{Date.today}",
        upgrades_issue_body,
        upgrades_digest_label
    end
  end

  def create_issue(title, body, label)
    issue = digest_repo.issues.create! \
      user: User.staff_user,
      title: title,
      body: body,
      repository_id: digest_repo.id,
      labels: [label]
    Rails.logger.info "Created issue \"#{issue.title}\" (##{issue.number}) on repo #{digest_repo.nwo}"
  end

  def digest_repo
    @digest_repo ||= Repositories::Public.find_active!(REPO_ID)
  end

  def invitations_digest_label
    @invitations_digest_label ||= Label.find(INVITATION_REVIEW_LABEL_ID)
  end

  def upgrades_digest_label
    @upgrades_digest_label ||= Label.find(UPGRADE_REVIEW_LABEL_ID)
  end

  def invitations_issue_body
    <<-BODY
Hi #{issue_mentions}!

New organizations that have recently been invited to an enterprise account can be marked as completed at https://admin.github.com/stafftools/enterprises/organization_invitations

### Organization invitations awaiting review

#{invitations_issue_list(pending_invitations, list_style: "- [ ]")}

When all organizations have been reviewed, this issue can be closed.

_Note: This weekly digest issue was [generated automatically](https://github.com/github/meao/wiki/Field-Operations-Weekly-Digest-Issues). Please report any issues to [`@github/meao`](https://github.com/github/meao/issues/new/choose)._

---

#{field_operations_notes}
    BODY
  end

  def invitations_issue_list(invitations, pending_review: true, list_style: "-")
    unless invitations.any?
      return pending_review ? "- No recent invitations" : "- No recently reviewed invitations"
    end

    invitations.map do |invitation|
      [
        list_style,
        "#{(invitation.completed_at || invitation.confirmed_at).to_date}:",
        "[Organization #{invitation.invitee.name}](https://admin.github.com/stafftools/users/#{invitation.invitee.login})",
        "invited to",
        "[enterprise #{invitation.business.name}](https://admin.github.com/stafftools/enterprises/#{invitation.business.slug})"
      ].join(" ")
    end.join("\n")
  end

  def upgrades_issue_body
    <<-BODY
Hi #{issue_mentions}!

New enterprise accounts that have recently been created as a result of standalone organizations being upgraded can be reviewed at https://admin.github.com/stafftools/enterprises/organization_upgrades

### New enterprise accounts awaiting review

#{upgrades_issue_list(upgraded_businesses_pending_review, list_style: "- [ ]")}

When all enterprise accounts have been reviewed, this issue can be closed.

_Note: This weekly digest issue was [generated automatically](https://github.com/github/meao/wiki/Field-Operations-Weekly-Digest-Issues). Please report any issues to [`@github/meao`](https://github.com/github/meao/issues/new/choose)._

---

#{field_operations_notes}
    BODY
  end

  def field_operations_notes
    <<-BODY
### Field Operations Notes

**Org ARR Transfers Completed:**

**Number** | **Transfer** | **Opp**| **ARR**| **Close Date**|**Sales Rep**| **Notify Comp?**
:--: | :--:| :--:| :--:| :--:| :--:| :--:
1 | ORG invited to ENTACC | [OPP](LINK) | ARR_TRANSFER_AMOUNT| OPP_CLOSE_DATE | `REP` | Y/N
2 | ORG invited to ENTACC | [OPP](LINK) | ARR_TRANSFER_AMOUNT| OPP_CLOSE_DATE | `REP` | Y/N
3 | ORG invited to ENTACC | [OPP](LINK) | ARR_TRANSFER_AMOUNT| OPP_CLOSE_DATE | `REP` | Y/N

---

👋 `@github/salescomp` please note adjustments made on the above opps ☝️

### AMER
**Number** | **Rep**
:--: | :--:
`#` | @REP

### EMEA
**Number** | **Rep**
:--: | :--:
`#` | @REP

### APAC
**Number** | **Rep**
:--: | :--:
`#` | @REP

cc// MANAGER_TAG_LIST
    BODY
  end

  def upgrades_issue_list(businesses, pending_review: true, list_style: "-")
    unless businesses.any?
      return pending_review ? "- No recent upgrades" : "- No recently reviewed upgrades"
    end

    businesses.map do |business|
      parts = [
        list_style,
        "#{(business.upgrade_reviewed_at || business.upgraded_at).to_date}:",
        "Enterprise [#{business.name}](https://admin.github.com/stafftools/enterprises/#{business.slug})",
        "created via upgrade",
      ]
      if business.upgraded_from.present?
        parts << "from organization [#{business.upgraded_from.name}](https://admin.github.com/stafftools/users/#{business.upgraded_from.login})"
      end
      parts.join(" ")
    end.join("\n")
  end

  def pending_invitations
    BusinessOrganizationInvitation.joins(:business).pending_completion.all
  end

  def upgraded_businesses_pending_review
    Business.upgraded_and_not_reviewed.includes(:upgraded_from).order("upgraded_at DESC").all
  end

  def issue_mentions
    ["@github/field-operations"].join(" ")
  end
end
