# typed: strict
# frozen_string_literal: true

module Codespaces
  module Organizations
    module Settings
      class UserAccessForm < ApplicationForm
        extend T::Sig
        include GitHub::Memoizer

        @radio_button_checked_proc = T.let(T.unsafe(nil), T.untyped)
        @disable_form = T.let(T.unsafe(nil), T.untyped)

        sig { params(radio_button_checked_proc: T.proc.params(value: String).returns(T::Boolean), disable_form: T::Boolean).void }
        def initialize(radio_button_checked_proc:, disable_form:)
          @radio_button_checked_proc = T.let(radio_button_checked_proc, T.proc.params(value: String).returns(T::Boolean))
          @disable_form = T.let(disable_form, T::Boolean)
        end

        form do |user_access_form|
          user_access_form.radio_button_group(name: "organization_codespaces_user_limit", label: nil, mt: 3) do |enablement_group|
            enablement_group.radio_button(
              value: Configurable::OrganizationCodespacesUserLimit::DISABLED,
              label: "Disabled",
              caption: "Disable GitHub Codespaces for all organization owned private and internal repositories",
              checked: @radio_button_checked_proc.call(Configurable::OrganizationCodespacesUserLimit::DISABLED),
              disabled: @disable_form,
              data: {
                "required-change" => ""
              }
            )
            enablement_group.radio_button(
              value: Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
              label: "Enable for specific members or teams",
              caption: "Enable GitHub Codespaces for specific organization members or teams on all organization owned private and internal repositories",
              checked: @radio_button_checked_proc.call(Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS),
              disabled: @disable_form,
              data: {
                "required-change" => ""
              }
            )
            enablement_group.radio_button(
              value: Configurable::OrganizationCodespacesUserLimit::ALL_USERS,
              label: "Enable for all members",
              caption: "Enable GitHub Codespaces for all organization members on all organization owned private and internal repositories",
              checked: @radio_button_checked_proc.call(Configurable::OrganizationCodespacesUserLimit::ALL_USERS),
              disabled: @disable_form,
              data: {
                "required-change" => ""
              }
            )
            enablement_group.radio_button(
              value: Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS,
              label: "Enable for all members and outside collaborators",
              caption: "Enable GitHub Codespaces for all organization members on all organization owned private and internal repositories",
              checked: @radio_button_checked_proc.call(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS),
              disabled: @disable_form,
              data: {
                "required-change" => ""
              }
            )
          end
          user_access_form.submit(
            name: :submit,
            label: "Save",
            disabled: @disable_form,
            mb: 3,
            aria: {
              label: "Save user access settings"
            }
          )
        end
      end
    end
  end
end
