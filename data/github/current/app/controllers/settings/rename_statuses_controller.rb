# typed: true
# frozen_string_literal: true

class Settings::RenameStatusesController < ApplicationController
  before_action :login_required
  before_action :ensure_valid_renamable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  # Renaming runs in the background. Once it begins, we display a spinner
  # saying "Your rename is in progress..." then poll this URL to see
  # if the rename has completed or not. Both orgs and users use this route.
  #
  # When a rename has succeeded it will return an HTML partial to replace
  # the poll-include-fragment element that was polling this endpoint.
  def show
    return head 202 if renamable.renaming?

    render partial: "settings/rename_statuses/show", locals: {
      renamable: renamable,
    }
  end

  private

  def target_for_conditional_access
    # This controller requires a renamable but this filter gets called before
    # anything else, so we have to handle the case where `renamable` is `nil`.
    return :no_target_for_conditional_access unless renamable.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    renamable
  end

  # We only want to show renaming status if the renamable exists and the
  # current user is can admin the renamable. This works if the current user is
  # the renamable, since `adminable_by?` is true in that case.
  def ensure_valid_renamable
    return render_404 unless renamable&.adminable_by?(current_user)
  end

  # The account that is being renamed, either a User or an Organization.
  memoize def renamable
    if params[:organization_id].present?
      Organization.find_by(id: params[:organization_id])
    else
      current_user
    end
  end
end
