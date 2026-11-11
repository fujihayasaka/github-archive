# typed: true
# frozen_string_literal: true

class Orgs::AttributionInvitationsController < Orgs::Controller # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :login_required
  before_action :organization_admin_required, except: :index

  def index
    invitations = AttributionInvitation.where(target: current_user, owner: this_organization)

    render "orgs/attribution_invitations/index", locals: { invitations: invitations }
  end

  def create
    source = Mannequin.find_by_login(params[:source_login])
    target = User.find_by_login(params[:target_login])

    unless source
      flash[:error] = "Could not find source mannequin with login #{params[:source_login]}"
    end

    unless target
      flash[:error] = "Could not find target user with login #{params[:target_login]}"
    end

    if source && target
      attribution_invitation = AttributionInvitation.new(
        source: source,
        target: target,
        owner: this_organization,
        creator: current_user,
      )

      if attribution_invitation.save
        flash[:notice] = "Successfully sent a reattribution invitation to #{target.display_login}"
      else
        flash[:error] = "Could not invite #{target.display_login} to claim this data"
      end
    end

    redirect_to settings_org_import_export_path(this_organization)
  end

  def target_suggestions # rubocop:todo GitHub/UseRestfulActions
    headers["Cache-Control"] = "no-cache, no-store"
    view = create_view_model(AutocompleteView,
      org_members_only: true,
      organization: this_organization,
      query: params[:q],
      business: this_organization&.business
    )

    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/attribution_invitations/target_suggestions", formats: :html, locals: { view: view }
      end
      format.html do
        render partial: "orgs/attribution_invitations/target_suggestions", locals: { view: view }
      end
    end
  end
end
