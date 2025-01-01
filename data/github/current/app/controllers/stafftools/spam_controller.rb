# typed: true
# frozen_string_literal: true

class Stafftools::SpamController < StafftoolsController
  before_action :ensure_spam_enabled
  before_action :ensure_user_exists

  # Sets the spammy flag on a user
  def create
    missing_fields = [:reason, :content_formats, :created_at, :source].select { |field| params[field].blank? }
    dsa_submission_not_required = DsaConstants::SUBMISSION_SKIPPABLE_VALUES.include?(params[:reason])

    if !dsa_submission_not_required && missing_fields.any?
      flash[:error] = "Could not mark user as spammy. Please submit responses for the required fields: #{missing_fields.join(", ")}"
      redirect_to :back
      return
    end

    source = dsa_submission_not_required ? nil : params[:source]

    flag_account(
      this_user,
      reason: params[:reason],
      paid_confirm: params[:paid_confirm],
      content_formats: params[:content_formats],
      created_at: params[:created_at],
      source: source,
      notes: params[:notes],
      items_reported_to_ncmec: params[:items_reported_to_ncmec]
    )
    flash[:notice] = "#{this_user.login} flagged as spammy"
    redirect_to :back
  end

  # Removes the spammy flag from a user
  def destroy
    this_user.mark_not_spammy(actor: current_user, origin: :stafftools)
    redirect_to :back
  end

  # Flag all other free users on the same IP as spam
  def flag_all # rubocop:todo GitHub/UseRestfulActions
    missing_fields = [:reason, :content_formats, :created_at, :source].select { |field| params[field].blank? }
    dsa_submission_not_required = DsaConstants::SUBMISSION_SKIPPABLE_VALUES.include?(params[:reason])

    if !dsa_submission_not_required && missing_fields.any?
      flash[:error] = "Could not mark users as spammy. Please submit responses for the required fields: #{missing_fields.join(", ")}"
      redirect_to :back
      return
    end

    source = dsa_submission_not_required ? nil : params[:source]

    users_flagged = 0
    User.transaction do
      User.by_ip(this_user.last_ip).each do |user|
        users_flagged += 1
        flag_account(
          user,
          reason: params[:reason],
          content_formats: params[:content_formats],
          created_at: params[:created_at],
          source: source,
          notes: params[:notes]
        )
      end
    end
    flash[:notice] = "All users (#{users_flagged}) on IP #{this_user.last_ip} flagged as spammy"
    redirect_to :back
  end

  # Allowlists the user from spam flagging
  def allowlist # rubocop:todo GitHub/UseRestfulActions
    this_user.mark_as_hammy(actor: current_user, origin: :stafftools)
    redirect_to :back
  end

  def toggle_renaming_or_deleting # rubocop:todo GitHub/UseRestfulActions
    Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: current_user, user: this_user, toggle_type: params[:toggle_type].to_sym)
    flash[:notice] = "Spammy account #{params[:toggle_type]} abilities changed."
    redirect_to :back
  end

  def toggle_override_for_owned_orgs # rubocop:todo GitHub/UseRestfulActions
    Stafftools::SpammyRenameDeleteOverride.toggle_override_for_owned_orgs(actor: current_user, user: this_user, toggle_type: params[:toggle_type].to_sym)
    flash[:notice] = "Spammy account #{params[:toggle_type]} abilities changed."
    redirect_to :back
  end

  private

  def ensure_spam_enabled
    render_404 unless GitHub.spamminess_check_enabled?
  end

  def flag_account(user, reason: nil, paid_confirm: false, content_formats: nil, created_at: nil, source: nil, notes: nil, items_reported_to_ncmec: nil)
    user.spammy_reason = nil  # to get around the allowlist
    reason ||= "Flagged by staff"
    created_at ||= DateTime.now.to_s

    user.mark_as_spammy(
      reason: reason,
      actor: current_user,
      origin: :stafftools,
      content_formats: content_formats,
      content_creation_date: DateTime.parse(created_at || DateTime.now.to_s),
      dsa_source: source,
      notes: notes,
      paid_confirm: paid_confirm,
      items_reported_to_ncmec:,
    )
  end
end
