# typed: true
# frozen_string_literal: true

module Orgs
  module Invitations
    class ReinstateView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      # A ViewModel for orgs/invitations/reinstate.html.erb
      #
      # Used when creating a membership directly, without creating an invitation
      # for a prospective organization member to accept first.
      class CreateMembershipImmediatelyView < CreateInvitationView
        def form_tag_arguments_reinstate_form
          action = urls.add_member_to_org_path(organization,
                                              invitee_id: user.id,
                                              role: :reinstate)
          [action, {
            :method => :post,
            :class => "js-togglable-form",
            :id => "reinstate-form",
            "data-sudo-required" => "true" }]
        end

        def form_submit_copy_reinstate_form
          "Add and reinstate"
        end

        def form_submit_copy_start_fresh_form
          "Add and start fresh"
        end
      end
    end
  end
end
