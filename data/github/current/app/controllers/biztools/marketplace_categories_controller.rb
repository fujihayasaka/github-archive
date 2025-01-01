# typed: true
# frozen_string_literal: true

class Biztools::MarketplaceCategoriesController < BiztoolsController

  before_action :marketplace_required
  before_action :cast_boolean_params, only: %i(create update)
  before_action :cast_integer_params, only: %i(create update)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :edit], optional: true

  def index
    marketplace_categories = Marketplace::Category.order(:name).not_sponsors_only

    respond_to do |format|
      format.html do
        render "biztools/marketplace_categories/index", locals: { marketplace_categories: marketplace_categories }
      end
    end
  end

  def new
    categories = Marketplace::Category.order(:name).not_sponsors_only
    categories = categories.subcategory_candidates(for_optional_slug: "")
    category_names = categories.pluck(:name)

    respond_to do |format|
      format.html do
        render "biztools/marketplace_categories/new", locals: { category_names: category_names }
      end
    end
  end

  def create
    category = Marketplace::Category.new
    set_category_attributes(category)

    if category.errors.blank? && category.save
      flash[:notice] = "Successfully created the Marketplace category"
      redirect_to biztools_marketplace_categories_path
    else
      flash[:error] = "Could not create the Marketplace category: #{category.errors.full_messages.join(", ")}"
      redirect_to biztools_new_marketplace_category_path
    end
  end

  def edit
    slug = params[:category_slug]
    category = Marketplace::Category.find_by!(slug: slug)
    categories = Marketplace::Category.order(:name).not_sponsors_only
    categories = categories.subcategory_candidates(for_optional_slug: slug)
    category_names = categories.pluck(:name)

    respond_to do |format|
      format.html do
        render "biztools/marketplace_categories/edit", locals: {
          category: category,
          category_names: category_names,
        }
      end
    end
  end

  def update
    category = Marketplace::Category.find_by!(slug: params[:category_slug])
    set_category_attributes(category)

    if category.errors.blank? && category.save
      flash[:notice] = "Successfully updated the Marketplace category"
      redirect_to biztools_marketplace_categories_path
    else
      flash[:error] = "Could not update the Marketplace category: #{category.errors.full_messages.join(", ")}"
      redirect_to biztools_edit_marketplace_category_path(params[:category_slug])
    end
  end

  private

  def marketplace_category_params
    params
      .require(:marketplace_category)
      .permit(:name, :description, :howItWorks, :isNavigationVisible,
              :isFilter, :isFeatured, :featuredPosition, subCategories: [])
  end

  def cast_boolean_params
    %i(isNavigationVisible isFilter isFeatured).each do |attr|
      if (bool_param = params.dig(:marketplace_category, attr)).present?
        params[:marketplace_category][attr] = ActiveModel::Type::Boolean.new.cast(bool_param)
      end
    end
  end

  def cast_integer_params
    %i(featuredPosition).each do |attr|
      if (int_param = params.dig(:marketplace_category, attr)).present?
        params[:marketplace_category][attr] = ActiveModel::Type::Integer.new.cast(int_param)
      else
        params[:marketplace_category].delete attr
      end
    end
  end

  def set_category_attributes(category)
    input = marketplace_category_params

    category.name = input[:name] if input.key?(:name)
    category.description = input[:description] if input.key?(:description)
    category.how_it_works = input[:howItWorks] if input.key?(:howItWorks)
    category.acts_as_filter = input[:isFilter] if input.key?(:isFilter)
    category.navigation_visible = input[:isNavigationVisible] if input.key?(:isNavigationVisible)
    category.featured = input[:isFeatured] if input.key?(:isFeatured)
    category.featured_position = input[:featuredPosition] if input.key?(:featuredPosition)

    if input.key?(:subCategories)
      sub_category_names = input[:subCategories].reject(&:blank?)
      sub_categories = Marketplace::Category.where(name: sub_category_names).to_a
      missing_names = sub_category_names - sub_categories.map(&:name)
      if missing_names.present?
        category.errors.add(:sub_categories, :missing, message: "do not exist: #{missing_names.join(", ")}")
      else
        category.sub_categories = sub_categories
      end
    end
  end
end
