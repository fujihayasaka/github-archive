# typed: true
# frozen_string_literal: true

module Orgs
  module Invitations
    class ReinstateView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      # A ViewModel for orgs/invitations/reinstate.html.erb
      #
      # Used when creating a new invitation.
      class CreateInvitationView < ReinstateView
        def editing_existing_invitation?
          false
        end

        def copy_do_you_want_to_reinstate
          "Do you want to reinstate their account?"
        end

        def radio_button_default_selection?(option:)
          option == :reinstate
        end

        def form_tag_arguments_reinstate_form
          action = urls.org_invitations_path(organization, invitee_id: user.id,
                                             role: :reinstate)
          [action, {
            :method => :post,
            :class => "js-togglable-form",
            :id => "reinstate-form",
            "data-sudo-required" => "true" }]
        end

        def form_tag_arguments_start_fresh_form
          action = urls.org_edit_invitation_path(organization, user)

          [action, {
            method: :get,
            class: "js-togglable-form d-none",
            id: "start-fresh-form" }]
        end

        def form_submit_copy_start_fresh_form
          enterprise_managed_user_enabled? ? "Add and start fresh" : "Invite and start fresh"
        end

        def form_submit_copy_reinstate_form
          enterprise_managed_user_enabled? ? "Add and reinstate" : "Invite and reinstate"
        end
      end
    end
  end
end
