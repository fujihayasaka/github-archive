# typed: true
# frozen_string_literal: true

class IntegrationListings::IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  def category_color(feature)
    case feature.slug
    when "collaborate"
      "marketing-turquoise-octicon"
    when "ship"
      "marketing-purple-octicon"
    when "github-enterprise"
      "marketing-purple-octicon"
    else
      "marketing-blue-octicon"
    end
  end

  def category_icon(feature)
    case feature.slug
    when "collaborate"
      "git-pull-request"
    when "ship"
      "rocket"
    when "github-enterprise"
      "mark-github"
    else
      "code"
    end
  end

  def categories
    IntegrationFeature.visible.ordered
  end

  def filters
    IntegrationFeature.filterable.ordered
  end
end
