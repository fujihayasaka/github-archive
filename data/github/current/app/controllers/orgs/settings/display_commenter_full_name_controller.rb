# typed: true
# frozen_string_literal: true

class Orgs::Settings::DisplayCommenterFullNameController < Orgs::Controller
  before_action :login_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    if !current_organization.plan_supports_display_commenter_full_name?(visibility: :private)
      supported_plans = GitHub::Plan.supported_org_plans_for_feature(
          feature: :display_commenter_full_name,
          visibilities: [:private],
        ).map(&:titleized_display_name).uniq
      plans_as_sentence = if supported_plans.count > 2
        supported_plans.to_sentence(last_word_connector: " or ")
      else
        supported_plans.to_sentence(two_words_connector: " or ")
      end
      flash[:error] = "Upgrade to #{plans_as_sentence} to enable this feature."
      redirect_to settings_org_member_privileges_path(current_organization)
    elsif %w[0 1].include?(params[:display_commenter_full_name])
      notice = if params[:display_commenter_full_name] == "1"
        current_organization.enable_display_commenter_full_name(actor: current_user)
        "Private repositories will now show comment author's full name."
      else
        current_organization.disable_display_commenter_full_name(actor: current_user)
        "Private repositories will not show comment author's full name."
      end

      redirect_to settings_org_member_privileges_path(current_organization), notice: notice
    else
      flash[:error] = "You specified an invalid value for the \"display comment " \
        "author's full name in private repositories\" setting."
      redirect_to settings_org_member_privileges_path(current_organization)
    end
  end
end
