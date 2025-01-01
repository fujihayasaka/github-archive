# typed: true
# frozen_string_literal: true

class Devtools::SurveysController < DevtoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  def index
    render "devtools/surveys/index", locals: {
      surveys: Survey.order(:created_at).paginate(page: current_page, per_page: DEFAULT_PER_PAGE)
    }
  end

  def batch # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.csv do
        @survey = Survey.find_by!(slug: params["slug"])
        if !GitHub.flipper[:devtools_batch_survey_download].enabled?(current_user)
          redirect_back fallback_location: devtools_surveys_path
          return
        end

        filename = "survey_#{@survey.slug}.csv"
        num_responses = params["num_responses"].to_i
        limit = num_responses >= 0 ? num_responses * @survey.questions.length : 0
        offset = params["offset"].to_i >= 0 ? params["offset"].to_i * @survey.questions.length : 0

        data = @survey.batch_csv_dump(offset, limit)

        send_data data, type: "text/csv",
                        disposition: "attachment;filename=#{filename}"
      end

      format.html do
        render "devtools/surveys/show", locals: { survey: Survey.find_by(slug: params["slug"]) }
      end
    end
  end

  def show
    @survey = Survey.find_by(slug: params["slug"])
    return render_404 unless @survey

    respond_to do |format|
      format.csv do
        filename = "survey_#{@survey.slug}.csv"
        data = @survey.csv_dump

        send_data data, type: "text/csv",
                        disposition: "attachment;filename=#{filename}"
      end

      format.html do
        render "devtools/surveys/show", locals: { survey: @survey }
      end
    end
  end

  private

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil,
      label: "Surveys",
      path: devtools_surveys_path,
      parent: ContextRegion::DevtoolsCrumb.new
    )
  end
end
