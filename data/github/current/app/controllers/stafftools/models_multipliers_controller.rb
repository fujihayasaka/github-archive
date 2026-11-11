# typed: true
# frozen_string_literal: true

class Stafftools::ModelsMultipliersController < StafftoolsController
  before_action :github_models_required
  before_action :ensure_multiplier_exists, only: [:edit, :update, :destroy]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :new, :edit]

  PER_PAGE = 30

  sig { void }
  def index
    models_multipliers = GitHubModels::Multiplier.includes(:model).order(:id)
    models_multipliers = models_multipliers.paginate(page: current_page, per_page: PER_PAGE)

    render "stafftools/models/multipliers/index", locals: {
      models_multipliers: models_multipliers,
      per_page: PER_PAGE,
    }
  end

  sig { void }
  def new
    multiplier = GitHubModels::Multiplier.new
    render "stafftools/models/multipliers/new", locals: { multiplier: multiplier }
  end

  sig { void }
  def create
    multiplier = GitHubModels::Multiplier.new(multiplier_params.except(:authenticity_token))
    if multiplier.save
      flash[:notice] = "Multiplier successfully created."
      redirect_to stafftools_models_multipliers_path
    else
      flash[:error] = "Couldn't create multiplier: #{multiplier.errors.full_messages.to_sentence}"
      render "stafftools/models/multipliers/new", locals: { multiplier: multiplier }
    end
  end

  sig { void }
  def edit
    render "stafftools/models/multipliers/new", locals: { multiplier: current_multiplier }
  end

  sig { void }
  def update
    if current_multiplier.update(multiplier_params)
      flash[:notice] = "Multiplier successfully updated."
      redirect_to stafftools_models_multipliers_path
    else
      flash[:error] =
        "Multiplier not updated. Errors: #{current_multiplier.errors.full_messages.to_sentence}."
      redirect_to edit_stafftools_models_multiplier_path(current_multiplier)
    end
  end

  sig { void }
  def destroy
    if current_multiplier&.destroy
      flash[:notice] = "Multiplier successfully deleted."
    else
      flash[:error] = "Could not delete multiplier."
    end
    redirect_to stafftools_models_multipliers_path
  end

  private

  memoize def current_multiplier
    GitHubModels::Multiplier.find_by(models_slug: params[:models_slug])
  end

  sig { returns(ActionController::Parameters) }
  def multiplier_params
    params.require(:github_models_multiplier).permit(:authenticity_token, :models_slug, :input, :cached_input, :output)
  end

  sig { void }
  def ensure_multiplier_exists
    render_404 unless current_multiplier
  end
end
