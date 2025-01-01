# typed: strict
# frozen_string_literal: true

# This controller is used to defer the loading of information
# about the use of dependencies. It fits the batch deferred
# interface which expects an input (except x-www-form-urlencoded):
#
#   items: {
#     item-0: { dependency_name: "" },
#     item-1: { dependency_name: "" },
#   }
#
# and returns a JSON response of key/HTML pairs:
#
#   {
#     item-0: "<div>...</div>",
#     item-1: "<div>...</div>"
#   }
#
# that will replace DOM elements with the rendered HTML.
#
# See https://github.com/orgs/github/teams/engineering/discussions/301
# for more information.
class Sponsors::BatchDeferredOssfScoresController < ApplicationController
  extend T::Sig

  before_action :login_required
  before_action :sponsors_required

  depends_on_clusters ApplicationRecord::Mysql1

  sig { void }
  def index
    batch_deferred_response = ossf_score_html
    respond_to do |format|
      format.json do
        render json: batch_deferred_response
      end
    end
  end

  private

  # Private: Extracts the items from the request parameters.
  # Expected parameter format:
  # {"item-0"=>
  #     {"dependency_name"=>""},
  #  "item-1"=>
  #     {"dependency_name"=>""},
  #    ...
  #   }
  sig { returns(T::Hash[String, T.untyped]) }
  def items
    return {} unless params[:items]
    params[:items].permit!.to_h.select { |_, inputs| inputs.key?(:dependency_name) }
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def ossf_score_html
    return {} unless items.any?
    items.each_with_object({}) do |(item, inputs), hash|
      dependency_name = inputs[:dependency_name]
      score = ossf_score(dependency_name)

      # Primer does not allow for custom background colors, so writing this color mapping using Primer's Label schemes:
      # https://primer.style/components/label/rails/beta
      colors = {
        "success" => "#1F883D",
        "orange" => "#BF8700",
        "attention" => "#9A6700",
        "danger" => "#CF222E",
        "gray" => "#D0D7DE",
        "black" => "#000000",
        "white" => "#FFFFFF"
      }

      color = case score
      when 7.5..Float::INFINITY
        colors["success"]
      when 5...7.5
        colors["orange"]
      when 3...5
        colors["attention"]
      when 0...3
        colors["danger"]
      else
        # When no score is available, score = false
        colors["gray"]
      end

      text_color = score == false ? colors["black"] : colors["white"]
      aria_label = score == false ? "No OpenSSF score available" : "OpenSSF score"
      test_selector = score == false ? "ossf-badge-no-score" : "ossf-badge"
      display_score = score == false ? "N/A" : score.to_s

      hash[item] = render_to_string(
          Primer::Beta::Label.new(
            **(if score
                 {
                   tag: :a,
                   target: "_blank",
                   href: "https://scorecard.dev/viewer/?uri=github.com/#{dependency_name}"
                 }
               else
                 {}
               end),
            style: "background-color:#{color}; color:#{text_color};",
            "aria-label": aria_label,
            test_selector: test_selector,
            layout: false
          ).with_content(display_score)
      )
    end
  end

  # Private: Fetches the OpenSSF score for a given repository.
  sig { params(repository_name: String).returns(T.any(Float, FalseClass)) }
  def ossf_score(repository_name)
    uri = URI.parse("https://api.securityscorecards.dev/projects/github.com/#{repository_name}")
    response = Net::HTTP.get_response(uri)
    if response&.code == "200"
      data = JSON.parse(response.body)
      data["score"]
    else
      false
    end
  end

  sig { returns T.any(User, Symbol) }
  def target_for_conditional_access
    # no protected resources provided by this controller
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
