# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class OverrideSpammyRenamingDeletingAbilitiesJob < ApplicationJob
  queue_as :spam
  retry_on_dirty_exit

  # Find all the spammy orgs that a spammy user owns and enable or disable an
  # override to allow/disallow renaming/deleting their own orgs.
  #
  #
  # actor        - user ID of staff member that initiated this action
  # user         - user ID whose overrride is being enabled/disabled
  # toggle_type  - one of the accepted actions defined in
  #                Stafftools::SpammyRenameDeleteOverride::ACCEPTED_TYPES
  # toggle_state - :enabled to enable the override (i.e., to *allow* them to
  #                perform the action), or :disabled to disable the override
  #                (i.e., to revoke their ability to perform the action)
  #
  # Returns nothing.
  def perform(actor, user, toggle_type, toggle_state = :enabled)
    user = User.find_by_id(user)
    actor = User.find_by_id(actor)

    return unless orgs = user.owned_organizations
    toggle(orgs: orgs, type: toggle_type, state: toggle_state, actor: actor)

    user_override = ::Stafftools::SpammyRenameDeleteOverride.new(actor:, user:, toggle_type:)
    with_write do
      if toggle_state == :disabled
        user_override.delete_org_override!
      else
        user_override.enable_org_override!
      end
    end
  end

  def toggle(orgs:, type:, state:, actor:)
    orgs.each do |org|
      begin
        if org.spammy?
          instance = ::Stafftools::SpammyRenameDeleteOverride.new(actor: actor, user: org, toggle_type: type)

          with_write do
            if state == :disabled
              instance.delete_override!
            else
              instance.enable_override!
            end
          end
        end
      rescue ActiveRecord::RecordNotFound => boom
        Failbot.report(boom)
        next
      end
    end
  end
end
