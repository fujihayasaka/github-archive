# typed: true
# frozen_string_literal: true

class CopilotSessions::UsersController < ApplicationController
  MAX_USER_IDS = 100

  before_action :login_required
  before_action :reject_enterprise
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Domain::Users,

  def index
    user_ids = params[:user_ids].to_s.split(",").map(&:to_i).first(MAX_USER_IDS)
    candidates = User.where(type: "User", id: user_ids).limit(MAX_USER_IDS).to_a

    target_emu_business_by_user_id = enterprise_managed_business_id_by_user_id(candidates.map(&:id))
    viewer_emu_business_id = current_user.is_enterprise_managed? ? current_user.enterprise_managed_business&.id : nil

    users = candidates
      .select { |user| visible_to_current_user?(user, target_emu_business_by_user_id, viewer_emu_business_id) }
      .map { |user| ::CopilotSessions::Payloads::PublicUser.new(user).call }
    respond_to do |format|
      format.json do
        render json: {
          users: users
        }
      end
    end
  end

  private

  # CAP is not bypassed here: `before_action :login_required` ensures
  # authenticated users are always present when the action runs. The guard
  # below is necessary because the EmuVisibility CAP policy evaluates the
  # target before `login_required` can issue a redirect (i.e. the policy's
  # "applicable?" check fires at request setup time). If we returned nil for
  # unauthenticated requests the CAP framework would raise
  # ArgumentError: malformed request. Returning :no_target_for_conditional_access
  # for unauthenticated requests matches the pattern used by the sibling
  # CopilotSessions::AliveChannelsController.
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def reject_enterprise
    render_404 if GitHub.enterprise?
  end

  # Enterprise Managed Users are only visible to other members of the same
  # enterprise. See https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/understanding-iam-for-enterprises/abilities-and-restrictions-of-managed-user-accounts
  sig do
    params(
      user: User,
      target_emu_business_by_user_id: T::Hash[Integer, Integer],
      viewer_emu_business_id: T.nilable(Integer)
    ).returns(T::Boolean)
  end
  def visible_to_current_user?(user, target_emu_business_by_user_id, viewer_emu_business_id)
    target_business_id = target_emu_business_by_user_id[user.id]
    return true if target_business_id.nil?
    !viewer_emu_business_id.nil? && viewer_emu_business_id == target_business_id
  end

  # Returns a `user_id => business_id` map of the EMU memberships for the given
  # user IDs. Uses two separate queries to avoid a cross-database JOIN:
  # BusinessUserAccount lives on ApplicationRecord::Collab while Business lives
  # on ApplicationRecord::Domain::Users, so a SQL JOIN across those two would
  # fail in environments where they are separate database servers (e.g. Proxima
  # multi-tenant mode).
  #
  # Both queries are bounded by `IN (...)` clauses on caller-supplied IDs (the
  # `user_ids` array is capped at MAX_USER_IDS in `index`), and each carries an
  # explicit `LIMIT` to keep Query Guard happy and to provide a hard ceiling on
  # the row count even if a future caller bypasses the cap.
  sig { params(user_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
  def enterprise_managed_business_id_by_user_id(user_ids)
    return {} if user_ids.empty?

    bua_pairs = BusinessUserAccount
      .where(user_id: user_ids)
      .limit(MAX_USER_IDS)
      .pluck(:user_id, :business_id)
    return {} if bua_pairs.empty?

    emu_business_id_set = Business
      .enterprise_managed
      .where(id: bua_pairs.map { |_, bid| bid }.uniq)
      .limit(MAX_USER_IDS)
      .pluck(:id)
      .to_set

    bua_pairs
      .select { |_, business_id| emu_business_id_set.include?(business_id) }
      .to_h
  end
end
