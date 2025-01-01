# typed: true
# frozen_string_literal: true

class PullRequests::DraftsUpgradeDialogComponent < ApplicationComponent
  extend T::Sig

  sig { returns T.nilable(Repository) }
  attr_reader :repository

  sig { returns T.nilable(User) }
  attr_reader :current_user

  sig { returns T.nilable(String) }
  attr_reader :location

  sig do params(
    repository: T.nilable(Repository),
    current_user: T.nilable(User),
    location: T.nilable(String)
  ).void
  end
  def initialize(repository:, current_user:, location:)
    @repository = repository
    @current_user = current_user
    @location = location
  end

  def render?
    current_user.present?
  end

  def dialog_close_hydro_attributes
    safe_data_attributes(
      hydro_click_tracking_attributes("dismiss_draft_pr_upgrade_dialog",
        category: "sculk_draft_pr_dropdown_option",
        action: "click_to_dismiss_draft_pr_dialog",
        label: "ref_cta:dismiss_draft_pr_dialog;ref_loc:pr_dropdown_option;"
      )
    )
  end
end
