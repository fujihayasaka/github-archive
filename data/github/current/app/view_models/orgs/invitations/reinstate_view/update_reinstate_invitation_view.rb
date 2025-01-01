# typed: true
# frozen_string_literal: true

module Orgs
  module Invitations
    class ReinstateView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      # A ViewModel for orgs/invitations/reinstate.html.erb
      #
      # Used when updating an invitation whose last saved state was as a
      # reinstate invitation (i.e., one which will restore the prospective
      # organization member's archived membership state) (i.e, one which has a
      # role attribute of :reinstate).
      class UpdateReinstateInvitationView < ReinstateView
        def editing_existing_invitation?
          true
        end

        def copy_do_you_want_to_reinstate
          "Do you still want to reinstate their account?"
        end

        def radio_button_default_selection?(option:)
          option == :reinstate
        end

        def form_tag_arguments_reinstate_form
          action = urls.org_invitation_path(organization, user,
                                            role: :reinstate)
          [action, {
            :method => :put,
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
          "Invite and start fresh"
        end

        def form_submit_copy_reinstate_form
          "Invite and reinstate"
        end
      end
    end
  end
end
