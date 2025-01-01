# typed: strict
# frozen_string_literal: true

module Actions
  module Policy
    class BusinessRepoSelfHostedRunnersForm < ApplicationForm
      extend T::Sig

      @entity = T.let(T.unsafe(nil), T.untyped)

      form do |repo_self_hosted_runners_form|
        repo_self_hosted_runners_form.check_box_group(
          label: "Choose which organizations are allowed to self manage self-hosted runners at the repository level.",
          label_arguments: {
            style: "font-weight:normal"
          }) do |check_group|
          check_group.check_box(
            name: "repo_self_hosted_runners_is_disabled",
            caption: "Repository-level runners will be disabled across all organizations in your Enterprise.",
            label: "Disable for all organizations",
            class: "form-checkbox-details-trigger",
            checked: @entity.repo_self_hosted_runners_disabled?,
          )

          if @entity.enterprise_managed_user_enabled?
            check_group.check_box(
              name: "repo_self_hosted_runners_is_disabled_for_emus",
              caption: "Repository runners will be disabled across all EMU personal namespaces in your organization.",
              label: "Disable for all Enterprise Managed User (EMU) repositories",
              class: "form-checkbox-details-trigger",
              checked: !@entity.repo_self_hosted_runners_enabled_for_emus?,
            )
          end
        end

        repo_self_hosted_runners_form.submit(
          name: "submit",
          label: "Save",
          aria: {
            label: "Save self-hosted runners settings"
          }
        )
      end

      sig { params(entity: T.any(User, Organization, Business)).void }
      def initialize(entity:)
        @entity = T.let(entity, T.any(User, Organization, Business))
      end
    end
  end
end
