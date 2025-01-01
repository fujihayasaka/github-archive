# typed: strict
# frozen_string_literal: true

class Repos::FormsController < ApplicationController
  extend T::Sig
  include Repos::OwnerRepoSelectionsPayloadHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:owner_items, :owner_detail, :fork_owner_items]

  before_action :require_xhr
  before_action :login_required

  sig { void }
  def owner_items # rubocop:todo GitHub/UseRestfulActions
    owners_hash = accessible_owners_hash(cap_filter, current_user)
    render json: { owners: owner_items_payload(owners_hash, current_user) }
  end

  sig { void }
  def fork_owner_items # rubocop:todo GitHub/UseRestfulActions
    repo = Repository.find_by(id: params[:repo_id])
    return render_404 unless repo

    owners_hash = accessible_fork_owners_hash(cap_filter, current_user, repo)
    render json: { owners: owner_items_payload(owners_hash, current_user) }
  end

  sig { void }
  def owner_detail # rubocop:todo GitHub/UseRestfulActions
    owner_payload = if params[:form] == "transfer"
      repo = Repository.find_by(id: params[:repo_id])
      return render_404 unless repo

      initial_owner_from_param_payload(params[:owner], cap_filter, current_user, repo, transfer: true)
    else
      initial_owner_from_param_payload(params[:owner], cap_filter, current_user)
    end
    return render_404 unless owner_payload

    render json: owner_payload
  end

  private

  sig { returns(Symbol) }
  def target_for_conditional_access
    # These methods are used out of the context of any org/business.
    # Orgs are already constrained by a CAP filter at OwnerRepoSelectionsPayloadHelper
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns(T.untyped) }
  def resource_for_conditional_access
    self
  end
end
