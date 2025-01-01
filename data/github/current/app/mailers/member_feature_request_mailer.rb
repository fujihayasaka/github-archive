# typed: true
# frozen_string_literal: true

class MemberFeatureRequestMailer < ApplicationMailer
  include GitHub::RouteHelpers

  self.mailer_name = "mailers/member_feature_request"
  layout "layouts/primer_layout"

  def notify_dismissal(member_feature_request)
    @member_feature_request = member_feature_request
    @feature = member_feature_request.feature
    @organization = member_feature_request.organization
    @requester = member_feature_request.requester
    @owner_contact_url = org_people_url(@organization, query: "role:owner")
    @subject = "Your #{@feature.name} access request was declined"

    premail(
      from: github_noreply,
      to: user_email(@requester),
      subject: "[GitHub] #{@subject}",
    )
  end
end
