# typed: true
# frozen_string_literal: true

class Biztools::MarketplaceCreatorVerificationController < BiztoolsController
  before_action :marketplace_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  def index
    current_state = if params[:state].present?
      params[:state]
    else
      "APPLIED"
    end

    search_state = 0
    if current_state == "APPLIED"
      search_state = Configurable::MarketplaceCreatorVerification::APPLIED
    elsif current_state == "REJECTED"
      search_state = Configurable::MarketplaceCreatorVerification::REJECTED
    elsif current_state == "APPROVED"
      search_state = Configurable::MarketplaceCreatorVerification::APPROVED
    elsif current_state == "ANY_STATE"
      search_states = [Configurable::MarketplaceCreatorVerification::APPLIED, Configurable::MarketplaceCreatorVerification::REJECTED, Configurable::MarketplaceCreatorVerification::APPROVED]
    end

    name = if params[:query].present?
      params[:query]
    else
      nil
    end

    creators = []
    if search_states != nil
      search_states.each do |state|
        creator = Configurable::MarketplaceCreatorVerification.pending_verification_request(state, name)
        creators << creator
      end
      creators = creators.flatten.uniq.paginate(page: current_page)
    else
      creators = Configurable::MarketplaceCreatorVerification.pending_verification_request(search_state, name).paginate(page: current_page)
    end

    render "biztools/marketplace_creators/creator_verification", locals: { creators: creators, current_state: current_state, query: params[:query] }
  end

  def show
    creator = Organization.find(params[:id])
    render "biztools/marketplace_creators/creator_verification_show", locals: { creator: creator }
  end

  def verify # rubocop:todo GitHub/UseRestfulActions
    creator = Organization.find(params[:creator_id])
    # only site admin can approve the request
    if current_user.site_admin?
      mailer_params = { to: T.must(creator.profile).email, publisher_name: creator.login, verified: params[:verify] == "true", reason: nil, custom_reason: nil, removing: params[:removing] }
      if params[:verify] == "true"
        creator.creator_verification_state_update(current_user, Configurable::MarketplaceCreatorVerification::APPROVED)
        flash[:notice] = "Verified #{creator.login}. Search results should be updated within a few moments"
      elsif !params[:reason]
        flash[:error] = "A reason is required to remove verification for #{creator.login}"
        mailer_params = nil
      else
        if params[:reason] == "CUSTOM_REASON"
          mailer_params[:custom_reason] = params[:custom_reason].strip
          if mailer_params[:custom_reason].empty?
            flash[:error] = "A message is required to remove verification for #{creator.login}"
            mailer_params = nil
          end
        end
        unless mailer_params.nil?
          creator.creator_verification_state_update(current_user, Configurable::MarketplaceCreatorVerification::REJECTED)
          flash[:notice] = "Removed verification for #{creator.login}. Search results should be updated within a few moments"
          mailer_params[:reason] = params[:reason]
        end
        mailer_params = nil if params[:reason] == "WILL_NOTIFY_MANUALLY"
      end
    end
    MarketplaceMailer.send(:creator_verification_update, **mailer_params).deliver_later if mailer_params
    redirect_to biztools_marketplace_creator_verification_path(query: params[:query], state: params[:state])
  end

end
