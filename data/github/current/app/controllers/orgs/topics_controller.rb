# typed: true
# frozen_string_literal: true

class Orgs::TopicsController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:most_used]

  TOPICS_PER_PAGE = 15

  before_action :login_required, except: :most_used
  before_action :ensure_trade_restrictions_allows_org_settings_access, unless: :xhr?, except: :most_used
  before_action :organization_read_required, only: [:index]

  def most_used # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/topics/most_used", formats: :html, locals: {
          view: create_view_model(Orgs::Repositories::IndexPageView,
            organization: this_organization,
            current_page: current_page,
            type_filter: params[:type],
            phrase: params[:q],
            language: params[:language],
            context: params[:context],
            cap_filter:,
          ),
        }
      end
    end
  end

  def index
    repositories = this_organization.repositories_with_topic_manage_access(
      viewer: current_user,
    ).simple_paginate(page: current_page, per_page: TOPICS_PER_PAGE)

    respond_to do |format|
      format.html do
        if xhr?
          # Requested from pagination links
          render partial: "orgs/topics/list", locals: { organization: this_organization, repositories: repositories }
        else
          render "orgs/topics/index", locals: { organization: this_organization, repositories: repositories }
        end
      end
    end
  end

  private

  def xhr?
    request.xhr? && !pjax?
  end
end
