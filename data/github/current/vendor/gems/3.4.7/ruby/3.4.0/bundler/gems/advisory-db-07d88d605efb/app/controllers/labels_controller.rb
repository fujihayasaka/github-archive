# frozen_string_literal: true

class LabelsController < InboxController
  def index; end

  def new
    render locals: { label: Label.new }
  end

  def create
    label = Label.new(label_params)
    label.label_settings = label_settings_from_params

    if label.save
      redirect_to label,
        notice: "Label #{label.name} was created successfully!"
    else
      render action: :new, status: :unprocessable_entity, locals: {
        label: label,
      }
    end
  end

  def show
    label = Label.find(params[:id])
    render locals: {
      label: label,
      labeled_reviews: label.advisory_reviews.paginate(page: params[:page]),
    }
  end

  def edit
    label = Label.find(params[:id])
    render locals: { label: label }
  end

  def update
    label = Label.find(params[:id])
    label.update(label_params)
    label.label_settings = label_settings_from_params

    if label.save
      redirect_to label,
        notice: "Label #{label.name} was saved successfully!"
    else
      render action: :edit, status: :unprocessable_entity, locals: {
        label: label,
      }
    end
  end

  def destroy
    label = Label.find(params[:id])
    name = label.name
    label.destroy!

    redirect_to labels_path,
      notice: "Label #{name} was deleted successfully!"
  end

  private

  def label_params
    params.require(:label).permit(:name, :description, :color)
  end

  def label_settings_from_params
    label_settings_params = params.require(:label).permit(label_settings: [:hold_publication])
    LabelSettings.adapt_params(label_settings_params[:label_settings])
  end
end
