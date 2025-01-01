# typed: true
# frozen_string_literal: true

class Orgs::People::FailedInvitationsPageView < Orgs::OverviewView
  INVITATIONS_PER_PAGE = 30

  attr_reader :organization, :page, :query, :role

  def initialize(**args)
    super(args)
    @context = args[:context] || :modal
    @invitations = args[:invitations]
    @organization = args[:organization]
  end

  def page_title
    "People · #{organization.safe_profile_name}"
  end

  def invitations
    @invitations.paginate(page: page, per_page: INVITATIONS_PER_PAGE)
  end

  def total_count
    @invitations.length
  end

  def show_admin_stuff?
    organization.adminable_by?(current_user)
  end

  def invitations_empty?
    invitations.empty?
  end
end
