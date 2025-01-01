# typed: true
# frozen_string_literal: true

class Site::Readme::NominateController < Site::Readme::BaseController
  before_action :login_required
  skip_before_action :add_csp_exceptions
  skip_before_action :set_flash_if_nomination_submitted

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    survey = Site::Readme::NominationSurvey.survey

    if survey.present?
      render "site/readme/nominate/show", locals: {
        survey: survey
      }
    else
      render_404
    end
  end
end
